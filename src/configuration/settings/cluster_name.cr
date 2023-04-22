class Configuration::Settings::ClusterName
  getter cluster_name : String
  getter errors : Array(String)

  def initialize(@errors, @cluster_name)
  end

  def validate
    if cluster_name.empty?
      errors << "cluster_name is an invalid format (only lowercase letters, digits and dashes are allowed)"
    elsif ! /\A[a-z\d-]+\z/.match(cluster_name)
      errors << "cluster_name is an invalid format (only lowercase letters, digits and dashes are allowed)"
    elsif ! /\A[a-z]+.*([a-z]|\d)+\z/.match(cluster_name)
      errors << "Ensure that cluster_name starts and ends with a normal letter"
    end
  end
end
