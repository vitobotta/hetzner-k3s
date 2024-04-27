require "./configuration/main"

class ClusterState
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  property seed_master_install_script_sha256 : String = ""
  property other_master_install_script_sha256 : String = ""
  property worker_install_script_sha256 : String = ""

  def self.read(state_file_path : String) : ClusterState
    ClusterState.from_yaml(File.read(state_file_path))
  end

  def write(state_file_path : String)
    File.write(state_file_path, self.to_yaml)
  end
end
