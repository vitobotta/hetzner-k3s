class Configuration::Settings::NodePool::PoolName
  getter errors : Array(String)
  getter pool_type : Symbol
  getter pool_name : String

  def initialize(@errors, @pool_type, @pool_name)
  end

  def validate
    return if pool_type == :masters || valid_pool_name?(pool_name)

    errors << "#{pool_type} has an invalid name"
  end

  private def valid_pool_name?(name : String) : Bool
    (name =~ /\A([A-Za-z0-9\-_]+)\Z/) != nil
  end
end
