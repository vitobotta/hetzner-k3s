require "./routing_spec_helper"

private PRIVATE_KEY = File.read("#{__DIR__}/fixtures/test_ssh_key")
private PUBLIC_KEY  = File.read("#{__DIR__}/fixtures/test_ssh_key.pub").strip

private def ssh_model(yaml : String = %(port: 22))
  Configuration::Models::NetworkingConfig::SSH.from_yaml(yaml)
end

private def ssh_errors(model : Configuration::Models::NetworkingConfig::SSH)
  errors = [] of String
  Configuration::Validators::NetworkingConfig::SSH.new(errors, model).validate
  errors
end

private def with_ssh_env(private_key : String? = nil, public_key : String? = nil, &)
  home = File.tempname("ssh-key-env-spec")
  Dir.mkdir(home)

  previous_home = ENV["HOME"]?
  previous_private = ENV["SSH_PRIVATE_KEY"]?
  previous_public = ENV["SSH_PUBLIC_KEY"]?

  ENV["HOME"] = home

  if private_key.nil?
    ENV.delete("SSH_PRIVATE_KEY")
  else
    ENV["SSH_PRIVATE_KEY"] = private_key
  end

  if public_key.nil?
    ENV.delete("SSH_PUBLIC_KEY")
  else
    ENV["SSH_PUBLIC_KEY"] = public_key
  end

  Util::SSHKeyEnv.reset!
  yield home
ensure
  if previous_home.nil?
    ENV.delete("HOME")
  else
    ENV["HOME"] = previous_home
  end

  if previous_private.nil?
    ENV.delete("SSH_PRIVATE_KEY")
  else
    ENV["SSH_PRIVATE_KEY"] = previous_private
  end

  if previous_public.nil?
    ENV.delete("SSH_PUBLIC_KEY")
  else
    ENV["SSH_PUBLIC_KEY"] = previous_public
  end

  Util::SSHKeyEnv.reset!
  FileUtils.rm_rf(home.not_nil!)
end

describe Util::SSHKeyEnv do
  it "leaves the configured paths alone without the variables" do
    with_ssh_env do
      model = ssh_model(%(private_key_path: "~/.ssh/cluster"\npublic_key_path: "~/.ssh/cluster.pub"))

      Util::SSHKeyEnv.private_key?.should be_false
      model.private_key_path.should end_with("/.ssh/cluster")
      model.public_key_path.should end_with("/.ssh/cluster.pub")
    end
  end

  it "treats an empty variable as unset" do
    with_ssh_env(private_key: "  ") do
      Util::SSHKeyEnv.private_key?.should be_false
      ssh_model.public_key_path.should_not be_empty
    end
  end

  it "writes the private key with 0600 and overrides the configured path" do
    with_ssh_env(private_key: PRIVATE_KEY) do |home|
      model = ssh_model(%(private_key_path: "/nonexistent/cluster"))

      path = model.private_key_path
      path.should start_with("#{home}/.hetzner-k3s/ssh/id_")
      File.read(path).should eq(PRIVATE_KEY)
      File.info(path).permissions.value.should eq(0o600)
    end
  end

  it "derives the public key from the private key when only the private one is set" do
    with_ssh_env(private_key: PRIVATE_KEY) do |home|
      model = ssh_model(%(public_key_path: "/nonexistent/cluster.pub"))

      public_path = model.public_key_path
      public_path.should start_with("#{home}/.hetzner-k3s/ssh/id_")
      File.read(public_path).split(' ')[0, 2].should eq(PUBLIC_KEY.split(' ')[0, 2])
    end
  end

  it "uses the public key variable when both are set and keeps the pair consistent" do
    with_ssh_env(private_key: PRIVATE_KEY, public_key: PUBLIC_KEY) do |home|
      model = ssh_model

      File.read(model.private_key_path).should eq(PRIVATE_KEY)
      File.read(model.public_key_path).strip.should eq(PUBLIC_KEY)
      model.public_key_path.should start_with("#{home}/.hetzner-k3s/ssh/id_")
    end
  end

  it "accepts the public key alone" do
    with_ssh_env(public_key: PUBLIC_KEY) do |home|
      model = ssh_model(%(private_key_path: "~/.ssh/cluster"))

      model.private_key_path.should end_with("/.ssh/cluster")
      model.public_key_path.should start_with("#{home}/.hetzner-k3s/ssh/id_")
    end
  end

  it "normalises escaped newlines and a missing trailing newline" do
    escaped = PRIVATE_KEY.strip.gsub("\n", "\\n")
    with_ssh_env(private_key: escaped) do
      File.read(ssh_model.private_key_path).should eq(PRIVATE_KEY)
    end
  end

  it "keeps the materialised path stable for the same content" do
    with_ssh_env(private_key: PRIVATE_KEY) do
      first = ssh_model.private_key_path
      Util::SSHKeyEnv.reset!

      ssh_model.private_key_path.should eq(first)
    end
  end

  it "reports a private key that is not a key" do
    with_ssh_env(private_key: "not a key") do
      ssh_errors(ssh_model).join.should contain("SSH_PRIVATE_KEY is set but does not contain an OpenSSH or PEM private key")
    end
  end

  it "reports a public key that is not a key" do
    with_ssh_env(public_key: "not a key") do
      ssh_errors(ssh_model).join.should contain("SSH_PUBLIC_KEY is set but does not contain a valid OpenSSH public key")
    end
  end

  it "reports a derivation failure" do
    with_ssh_env(private_key: "-----BEGIN OPENSSH PRIVATE KEY-----\ngarbage\n-----END OPENSSH PRIVATE KEY-----") do
      ssh_errors(ssh_model).join.should contain("Could not derive a public key from SSH_PRIVATE_KEY")
    end
  end

  it "rejects the ssh agent together with the private key variable" do
    with_ssh_env(private_key: PRIVATE_KEY) do
      errors = ssh_errors(ssh_model(%(use_agent: true)))

      errors.join.should contain("use_agent is true, so SSH_PRIVATE_KEY would be ignored")
    end
  end
end
