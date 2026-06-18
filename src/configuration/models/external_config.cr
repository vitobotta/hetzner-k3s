require "yaml"
require "./external_node"

class Configuration::Models::ExternalConfig
  include YAML::Serializable

  property nodes : Array(Configuration::Models::ExternalNode) = [] of Configuration::Models::ExternalNode

  def initialize
  end
end
