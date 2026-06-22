require "yaml"
require "./external_node"

class Configuration::Models::ExternalConfig
  include YAML::Serializable

  PROVIDER_GENERIC = "generic"
  PROVIDER_ROBOT   = "robot"

  property provider : String = PROVIDER_GENERIC
  property robot_user : String = ENV.fetch("ROBOT_USER", "")
  property robot_password : String = ENV.fetch("ROBOT_PASSWORD", "")
  property nodes : Array(Configuration::Models::ExternalNode) = [] of Configuration::Models::ExternalNode

  def initialize
  end

  def generic? : Bool
    provider == PROVIDER_GENERIC
  end

  def robot? : Bool
    provider == PROVIDER_ROBOT
  end
end
