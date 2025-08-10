class Configuration::Validators::ClusterName
  getter cluster_name : String
  getter errors : Array(String)

  def initialize(@errors, @cluster_name)
  end

  def validate
    return errors << "cluster_name is an invalid format (only lowercase letters, digits and dashes are allowed)" if cluster_name.empty?
    return errors << "cluster_name is an invalid format (only lowercase letters, digits and dashes are allowed)" unless /\A[a-z\d-]+\z/.match(cluster_name)
    return errors << "Ensure that cluster_name starts and ends with a normal letter" unless /\A[a-z]+.*([a-z]|\d)+\z/.match(cluster_name)
  end
end