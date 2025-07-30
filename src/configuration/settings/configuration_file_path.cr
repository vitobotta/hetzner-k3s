class Configuration::Settings::ConfigurationFilePath
  getter path : String
  getter errors : Array(String)

  def initialize(@errors, @path)
  end

  def validate
    configuration_file_path = Path[@path].expand(home: true).to_s
    return errors << "Configuration file not found at #{configuration_file_path}" unless File.exists?(configuration_file_path)

    errors << "Configuration path points to a directory, not a file" if File.directory?(configuration_file_path)
  end
end
