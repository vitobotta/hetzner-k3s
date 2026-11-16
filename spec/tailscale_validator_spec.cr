require "./routing_spec_helper"

def errors_for(yaml)
  tailscale = Configuration::Models::NetworkingConfig::Tailscale.from_yaml(yaml)
  errors = [] of String
  Configuration::Validators::NetworkingConfig::Tailscale.new(errors, tailscale).validate
  errors
end

describe Configuration::Validators::NetworkingConfig::Tailscale do
  it "accepts a disabled tailscale block regardless of its contents" do
    errors_for(<<-YAML).should be_empty
      enabled: false
      hostname_suffix: "not a domain"
      auth_key: "nope"
      YAML
  end

  it "accepts a complete tailscale block" do
    errors_for(<<-YAML).should be_empty
      enabled: true
      hostname_suffix: "tail1234ab.ts.net"
      auth_key: "tskey-auth-kExampleKey"
      version: "1.80.2"
      YAML
  end

  it "requires a hostname suffix" do
    errors_for(<<-YAML).join.should contain("hostname_suffix is required")
      enabled: true
      auth_key: "tskey-auth-kExampleKey"
      YAML
  end

  it "rejects a hostname suffix that is not a MagicDNS domain" do
    errors_for(<<-YAML).join.should contain("must be a MagicDNS domain")
      enabled: true
      hostname_suffix: "https://login.tailscale.com/admin/dns/"
      auth_key: "tskey-auth-kExampleKey"
      YAML
  end

  it "rejects an auth key from the wrong field" do
    errors_for(<<-YAML).join.should contain("should start with")
      enabled: true
      hostname_suffix: "tail1234ab.ts.net"
      auth_key: "kExampleKeyWithoutPrefix"
      YAML
  end

  it "rejects a version that is not a plain semantic version" do
    errors_for(<<-YAML).join.should contain("must be a plain version")
      enabled: true
      hostname_suffix: "tail1234ab.ts.net"
      auth_key: "tskey-auth-kExampleKey"
      version: "v1.80"
      YAML
  end
end
