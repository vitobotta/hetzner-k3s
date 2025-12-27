class Configuration::Validators::NetworkingConfig::CNIConfig::Cilium
  getter errors : Array(String)
  getter cilium : Configuration::Models::NetworkingConfig::CNIConfig::Cilium

  def initialize(@errors, @cilium)
  end

  def validate
    if cilium.helm_values_path
      path = cilium.helm_values_path.not_nil!
      if !File.exists?(path)
        errors << "Cilium helm_values_path '#{path}' does not exist"
      elsif !File.file?(path)
        errors << "Cilium helm_values_path '#{path}' is not a file"
      end
    end

    if cilium.chart_version.nil? || cilium.chart_version.empty?
      errors << "Cilium chart_version is required"
    end
  end
end