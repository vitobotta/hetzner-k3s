require "yaml"

require "./configuration/node_pool"

class Configuration
  include YAML::Serializable

  @[YAML::Field(key: "hetzner_token")]
  property hetzner_token : String?

  @[YAML::Field(key: "cluster_name")]
  property cluster_name : String?

  @[YAML::Field(key: "kubeconfig_path")]
  property kubeconfig_path : String?

  @[YAML::Field(key: "k3s_version")]
  property k3s_version : String?

  @[YAML::Field(key: "public_ssh_key_path")]
  property public_ssh_key_path : String?

  @[YAML::Field(key: "private_ssh_key_path")]
  property private_ssh_key_path : String?

  @[YAML::Field(key: "ssh_allowed_networks")]
  property ssh_allowed_networks : Array(String)?

  @[YAML::Field(key: "api_allowed_networks")]
  property api_allowed_networks : Array(String)?

  @[YAML::Field(key: "verify_host_key")]
  property verify_host_key : Bool?

  @[YAML::Field(key: "schedule_workloads_on_masters")]
  property schedule_workloads_on_masters : Bool?

  @[YAML::Field(key: "masters")]
  property masters : Configuration::NodePool?


  def vito
    puts "sddf"
  end
end
