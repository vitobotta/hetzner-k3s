require "./routing_spec_helper"

private def token_yaml(config_token : String?)
  return RoutingSpec.config unless config_token

  RoutingSpec.config.sub(%(hetzner_token: ""), "hetzner_token: #{config_token}")
end

private def with_env_token(value : String?, &)
  previous = ENV["HCLOUD_TOKEN"]?

  if value.nil?
    ENV.delete("HCLOUD_TOKEN")
  else
    ENV["HCLOUD_TOKEN"] = value
  end

  yield
ensure
  if previous.nil?
    ENV.delete("HCLOUD_TOKEN")
  else
    ENV["HCLOUD_TOKEN"] = previous
  end
end

private def resolved_token(config_token : String?) : String
  Configuration::Main.from_yaml(token_yaml(config_token)).hetzner_token
end

describe "the Hetzner token" do
  it "comes from the environment when both are set" do
    with_env_token("from-environment") do
      resolved_token("from-config").should eq("from-environment")
    end
  end

  it "falls back to the config file without the variable" do
    with_env_token(nil) do
      resolved_token("from-config").should eq("from-config")
    end
  end

  it "treats a blank variable as unset" do
    with_env_token("   ") do
      resolved_token("from-config").should eq("from-config")
    end
  end

  it "uses the variable when the config has no token" do
    with_env_token("from-environment") do
      resolved_token(nil).should eq("from-environment")
    end
  end

  it "is empty when neither is set" do
    with_env_token(nil) do
      resolved_token(nil).should be_empty
    end
  end

  it "satisfies the loader check with only the variable" do
    with_env_token("from-environment") do
      RoutingSpec.with_loader(token_yaml(nil)) do |loader|
        loader.settings.hetzner_token.should eq("from-environment")
        loader.errors.should_not contain("Hetzner API token is missing, please set it in the configuration file or in the environment variable HCLOUD_TOKEN")
      end
    end
  end

  it "keeps the config value when the variable is a placeholder" do
    with_env_token(nil) do
      resolved_token("use_hcloud_env_var").should eq("use_hcloud_env_var")
    end
  end
end

private def load_notice(yaml : String) : String
  output = IO::Memory.new
  File.tempfile("token-notice", ".yaml") do |file|
    file.print(yaml)
    file.flush
    Configuration::Loader.new(file.path, nil, false, false, output)
  end

  output.to_s
end

describe "the token precedence notice" do
  it "is printed once at load time" do
    with_env_token("from-environment") do
      load_notice(token_yaml("from-config")).should contain("[Configuration] HCLOUD_TOKEN is set and differs")
    end
  end

  it "prints nothing when the tokens agree" do
    with_env_token("same-token") { load_notice(token_yaml("same-token")).should be_empty }
  end

  it "names the source when both are set and differ" do
    with_env_token("from-environment") do
      notice = Configuration::Main.from_yaml(token_yaml("from-config")).token_precedence_notice.not_nil!

      notice.should contain("HCLOUD_TOKEN")
      notice.should contain("hetzner_token")
      notice.should_not contain("from-environment")
      notice.should_not contain("from-config")
    end
  end

  it "stays quiet when both are the same token" do
    with_env_token("same-token") do
      Configuration::Main.from_yaml(token_yaml("same-token")).token_precedence_notice.should be_nil
    end
  end

  it "stays quiet with only one of the two set" do
    with_env_token(nil) { Configuration::Main.from_yaml(token_yaml("from-config")).token_precedence_notice.should be_nil }
    with_env_token("from-environment") { Configuration::Main.from_yaml(token_yaml(nil)).token_precedence_notice.should be_nil }
    with_env_token("   ") { Configuration::Main.from_yaml(token_yaml("from-config")).token_precedence_notice.should be_nil }
  end
end
