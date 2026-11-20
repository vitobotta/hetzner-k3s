require "./routing_spec_helper"
require "compress/gzip"
require "../src/kubernetes/local_firewall/setup"
require "../src/hetzner/instance/create"

private def firewall_yaml(ips_token : String? = nil, config_token : String = "config-token", local_firewall : Bool = true)
  yaml = RoutingSpec.config(false)
    .sub(%(hetzner_token: ""), "hetzner_token: #{config_token}")
    .sub(/use_local_firewall: \w+/, "use_local_firewall: #{local_firewall}")

  return yaml unless ips_token

  yaml.sub("public_network:\n", "public_network:\n    hetzner_ips_token: \"#{ips_token}\"\n")
end

private class RecordingSSH < Util::SSH
  getter scripts = [] of String

  def initialize
    super("/nonexistent/key")
  end

  def run(instance, port, command, use_ssh_agent, print_output = true, disable_log_prefix = false, capture_output = false)
    @scripts << command
    ""
  end
end

private class InspectableFirewallSetup < Kubernetes::LocalFirewall::Setup
  getter recording = RecordingSSH.new

  def deploy_through(instance : Hetzner::Instance) : Nil
    deploy_firewall_files_with_ssh(instance, recording, 22, false, false)
  end
end

private def deploy(yaml : String) : String
  script = ""
  RoutingSpec.with_loader(yaml) do |loader|
    setup = InspectableFirewallSetup.new(loader.settings, Util::SSH.new("/nonexistent/key"))
    setup.deploy_through(RoutingSpec.master)
    script = setup.recording.scripts.first? || ""
  end

  script
end

private def decoded(script : String, path : String) : String
  line = script.lines.find { |l| l.includes?("> #{path}") }
  raise "no write for #{path}" unless line

  Base64.decode_string(line.split("'")[1])
end

# Runs only the definitions of the rendered script plus a direct call to fetch_node_ips, with the
# network commands stubbed out.
private def run_function(rendered : String, directory : String) : NamedTuple(output: String, calls: String)
  body = rendered.lines
  body.pop if body.last.try(&.includes?(%(main "$@")))

  stubs = [
    %{curl() { echo "$*" >> "$CALLS"; printf '%s' '["203.0.113.7"]'; }},
    %{jq() { case "$*" in *-r*) printf '%s\\n' "203.0.113.7" ;; *) cat >/dev/null ;; esac; }},
    %{sleep() { :; }},
  ].join("\n")

  script = stubs + "\n" + body.join("\n") + %{\nfetch_node_ips; echo "status=$?"\n}

  File.write("#{directory}/script.sh", script)
  output = IO::Memory.new
  Process.run("bash", ["#{directory}/script.sh"], {"CALLS" => "#{directory}/calls"}, output: output, error: output)
  {output: output.to_s, calls: File.read("#{directory}/calls")}
end

private def cloud_init(yaml : String) : String
  user_data = ""
  RoutingSpec.with_loader(yaml) do |loader|
    user_data = Hetzner::Instance::Create.cloud_init(loader.settings, 22, "default", [] of String, [] of String, [] of String, ["k3s install"], true)
  end

  user_data
end

private def decoded_cloud_init_file(user_data : String, path : String) : String
  lines = user_data.lines
  path_index = lines.index { |line| line.includes?("path: #{path}") }
  raise "no cloud-init entry for #{path}" unless path_index

  content_index = (0..path_index).to_a.reverse.find { |i| lines[i].strip.starts_with?("- content:") }
  raise "no content for #{path}" unless content_index

  inline = lines[content_index].split("content:", 2)[1].strip
  payload = if inline == "|"
              lines[(content_index + 1)...path_index].map(&.strip).reject(&.empty?).join
            else
              inline
            end

  inflate(Base64.decode(payload))
end

private def inflate(bytes : Bytes) : String
  io = IO::Memory.new(bytes)
  Compress::Gzip::Reader.open(io) { |gzip| gzip.gets_to_end }
end

describe "the local firewall token" do
  it "is no longer embedded in the rendered script" do
    rendered = decoded(deploy(firewall_yaml), "/usr/local/bin/firewall.sh")

    rendered.should_not contain("config-token")
    rendered.should contain("/etc/hetzner-k3s/hetzner-ips-token")
  end

  it "skips the API call when no token is readable" do
    rendered = decoded(deploy(firewall_yaml), "/usr/local/bin/firewall.sh")

    rendered.should contain(%(if [ -z "$HETZNER_TOKEN" ]))
    rendered.should contain(%([ -f "$LAST_IPS_FILE" ] && cat "$LAST_IPS_FILE"))
  end

  it "writes the token file 0600 and before the script when deploying over SSH" do
    script = deploy(firewall_yaml)

    script.should contain("chmod 600 /etc/hetzner-k3s/hetzner-ips-token")
    script.index("hetzner-ips-token").not_nil!.should be < script.index("/usr/local/bin/firewall.sh").not_nil!
    decoded(script, "/etc/hetzner-k3s/hetzner-ips-token").should eq("config-token")
  end

  it "uses hetzner_token as the fallback" do
    decoded(deploy(firewall_yaml), "/etc/hetzner-k3s/hetzner-ips-token").should eq("config-token")
  end

  it "uses the dedicated token when configured" do
    decoded(deploy(firewall_yaml(ips_token: "read-only-token")), "/etc/hetzner-k3s/hetzner-ips-token").should eq("read-only-token")
  end

  it "is also written by cloud-init, 0600, before the script" do
    user_data = cloud_init(firewall_yaml)

    user_data.should contain("path: /etc/hetzner-k3s/hetzner-ips-token")
    user_data.index("hetzner-ips-token").not_nil!.should be < user_data.index("/usr/local/bin/firewall.sh").not_nil!
    lines = user_data.lines
    entry = lines.index { |l| l.includes?("path: /etc/hetzner-k3s/hetzner-ips-token") }.not_nil!
    lines[entry..].first(4).join.should contain("permissions: '0600'")
    decoded_cloud_init_file(user_data, "/etc/hetzner-k3s/hetzner-ips-token").should eq("config-token")
  end

  it "honours the dedicated token in cloud-init too" do
    decoded_cloud_init_file(cloud_init(firewall_yaml(ips_token: "read-only-token")), "/etc/hetzner-k3s/hetzner-ips-token").should eq("read-only-token")
  end

  it "is not written when the local firewall is off" do
    cloud_init(firewall_yaml(local_firewall: false)).should_not contain("hetzner-ips-token")
  end
end

describe Configuration::Validators::NetworkingConfig::PublicNetwork do
  it "accepts an unset token" do
    errors = [] of String
    settings = Configuration::Main.from_yaml(firewall_yaml)
    Configuration::Validators::NetworkingConfig::PublicNetwork.new(errors, settings.networking.public_network, settings).validate

    errors.any?(&.includes?("hetzner_ips_token")).should be_false
  end

  it "rejects an empty token" do
    errors = [] of String
    settings = Configuration::Main.from_yaml(firewall_yaml(ips_token: "  "))
    Configuration::Validators::NetworkingConfig::PublicNetwork.new(errors, settings.networking.public_network, settings).validate

    errors.join.should contain("networking.public_network.hetzner_ips_token is set but empty")
  end
end

describe "at runtime" do
  it "sends the token from the file and returns the fetched addresses" do
    directory = File.tempname("firewall-token")
    Dir.mkdir(directory)
    begin
      rendered = decoded(deploy(firewall_yaml), "/usr/local/bin/firewall.sh")
        .sub("/etc/hetzner-k3s/hetzner-ips-token", "#{directory}/token")
        .sub("/tmp/last_node_ips.txt", "#{directory}/cache")
      File.write("#{directory}/token", "from-file")
      File.write("#{directory}/calls", "")
      result = run_function(rendered, directory)

      result[:output].should contain("203.0.113.7")
      result[:calls].should contain("Hetzner-Token: from-file")
    ensure
      FileUtils.rm_rf(directory)
    end
  end

  it "falls back to the cache without calling the API when the token file is missing" do
    directory = File.tempname("firewall-token")
    Dir.mkdir(directory)
    begin
      rendered = decoded(deploy(firewall_yaml), "/usr/local/bin/firewall.sh")
        .sub("/etc/hetzner-k3s/hetzner-ips-token", "#{directory}/token")
        .sub("/tmp/last_node_ips.txt", "#{directory}/cache")
      File.write("#{directory}/cache", "198.51.100.9\n")
      File.write("#{directory}/calls", "")
      result = run_function(rendered, directory)

      result[:output].should contain("198.51.100.9")
      result[:calls].should eq("")
    ensure
      FileUtils.rm_rf(directory)
    end
  end
end
