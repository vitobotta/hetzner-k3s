class Configuration::Settings::KubeconfigPath
  getter errors : Array(String)
  getter kubeconfig_path : String
  getter file_must_exist : Bool

  def initialize(@errors, @kubeconfig_path, @file_must_exist)
  end

  def validate
    if @kubeconfig_path
      if File.exists?(@kubeconfig_path) && File.directory?(@kubeconfig_path)
        errors << "kubeconfig_path already exists and it's a directory. We would need to write a kubeconfig file at that path"
      elsif @file_must_exist && !File.exists?(@kubeconfig_path)
        errors << "kubeconfig_path does not exist"
      end
    else
      errors << "kubeconfig_path is required"
    end
  end
end
