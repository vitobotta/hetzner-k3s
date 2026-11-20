require "./name_format"

class Configuration::Validators::ClusterName
  INVALID_FORMAT_MESSAGE = "cluster_name is an invalid format (#{Configuration::Validators::NameFormat::ALLOWED_CHARACTERS_DESCRIPTION})"

  getter cluster_name : String
  getter errors : Array(String)

  def initialize(@errors, @cluster_name)
  end

  def validate
    return errors << INVALID_FORMAT_MESSAGE if cluster_name.empty?
    return errors << INVALID_FORMAT_MESSAGE unless Configuration::Validators::NameFormat.allowed_characters?(cluster_name)
    return errors << "Ensure that cluster_name starts and ends with a normal letter" unless Configuration::Validators::NameFormat.starts_and_ends_correctly?(cluster_name)
  end
end
