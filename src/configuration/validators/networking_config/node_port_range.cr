class Configuration::Validators::NetworkingConfig::NodePortRange
  getter errors : Array(String)
  getter node_port_range : String

  def initialize(@errors, @node_port_range)
  end

  def validate
    unless node_port_range =~ /^\d+(-\d+)?$/
      errors << "networking.node_port_range must be a single port (\"30000\") or range (\"30000-32767\")"
      return
    end

    parts = node_port_range.split("-")
    if parts.size == 1
      validate_port(parts[0].to_i)
      return
    end

    start_port = parts[0].to_i
    end_port = parts[1].to_i

    if start_port > end_port
      errors << "networking.node_port_range must have start <= end (given #{node_port_range})"
      return
    end

    validate_port(start_port)
    validate_port(end_port)
  end

  private def validate_port(port : Int32) : Nil
    return if port >= 1 && port <= 65_535

    errors << "networking.node_port_range values must be between 1 and 65535 (given #{node_port_range})"
  end
end
