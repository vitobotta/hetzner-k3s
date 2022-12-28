
class Cluster
  include Utils

  def initialize(configuration:)
    @configuration = configuration
  end

  def upgrade(new_k3s_version:, config_file:)
    @cluster_name = configuration['cluster_name']
    @kubeconfig_path = File.expand_path(configuration['kubeconfig_path'])
    @new_k3s_version = new_k3s_version
    @config_file = config_file

    kubernetes_client.upgrade
  end

  def kubernetes_client
    @kubernetes_client ||= Kubernetes::Client.new(configuration: configuration)
  end


  def wait_for_servers(servers)
    threads = servers.map do |server|
      Thread.new { wait_for_ssh server }
    end

    threads.each(&:join) unless threads.empty?
  end

end
