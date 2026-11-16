require "./routing_spec_helper"
require "../src/configuration/validators/join_via_api_server_hostname"

private def join_via_api_server_hostname_errors(yaml : String) : Array(String)
  errors = [] of String
  RoutingSpec.with_loader(yaml) do |loader|
    Configuration::Validators::JoinViaApiServerHostname.new(errors, loader.settings).validate
  end
  errors
end

describe Configuration::Validators::JoinViaApiServerHostname do
  it "requires api_server_hostname when the flag is on" do
    errors = join_via_api_server_hostname_errors(RoutingSpec.config + "join_via_api_server_hostname: true\n")

    errors.should eq(["join_via_api_server_hostname requires api_server_hostname to be set"])
  end

  it "accepts the flag when a hostname is set" do
    errors = join_via_api_server_hostname_errors(
      RoutingSpec.config + "join_via_api_server_hostname: true\napi_server_hostname: k8s.example.com\n"
    )

    errors.should be_empty
  end

  it "does nothing when the flag is off" do
    errors = join_via_api_server_hostname_errors(RoutingSpec.config)

    errors.should be_empty
  end
end
