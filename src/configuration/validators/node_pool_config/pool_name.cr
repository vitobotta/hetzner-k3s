require "../name_format"

class Configuration::Validators::NodePoolConfig::PoolName
  getter errors : Array(String)
  getter pool_type : Symbol
  getter pool_name : String?

  def initialize(@errors, @pool_type, @pool_name)
  end

  def validate
    return if pool_type == :masters

    name = pool_name
    if name.nil? || name.empty?
      return errors << "#{pool_label} has no name. Set a name for each worker node pool."
    end

    unless Configuration::Validators::NameFormat.allowed_characters?(name)
      return errors << "#{pool_label} '#{name}' has an invalid name (#{Configuration::Validators::NameFormat::ALLOWED_CHARACTERS_DESCRIPTION})"
    end

    unless Configuration::Validators::NameFormat.starts_and_ends_correctly?(name)
      errors << "#{pool_label} '#{name}' must start with a lowercase letter and end with a lowercase letter or a digit"
    end
  end

  private def pool_label
    pool_type == :workers ? "Worker node pool" : "Master node pool"
  end
end
