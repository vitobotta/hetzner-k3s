require "../util"
require "../util/ssh"
require "../util/shell"
require "../hetzner/server"
require "../hetzner/load_balancer"
require "../configuration/loader"
require "file_utils"

class Kubernetes::Installer
  getter configuration : Configuration::Loader
  getter settings : Configuration::Main do
    configuration.settings
  end
  getter masters : Array(Hetzner::Server)
  getter workers : Array(Hetzner::Server)
  getter load_balancer : Hetzner::LoadBalancer?
  getter ssh : Util::SSH

  getter first_master : Hetzner::Server do
    masters[0]
  end

  getter api_server_ip_address : String do
    if masters.size > 1
      load_balancer.not_nil!.public_ip_address.not_nil!
    else
      first_master.public_ip_address.not_nil!
    end
  end

  getter tls_sans : String do
    sans = " --tls-san=#{api_server_ip_address} "

    masters.each do |master|
      master_private_ip = master.private_ip_address
      sans += " --tls-san=#{master_private_ip} "
    end

    sans
  end

  def initialize(@configuration, @masters, @workers, @load_balancer, @ssh)
  end

  def run
    # puts "\n=== Setting up Kubernetes ===\n"

    # set_up_first_master
    # set_up_other_masters
    # set_up_workers

    puts "\n=== Deploying Hetzner drivers ===\n"

    deploy_cloud_controller_manager
  end

  private def set_up_first_master
    puts "Deploying k3s to first master #{first_master.name}..."

    ssh.run(first_master, master_install_script(first_master))

    puts "Waiting for the control plane to be ready..."

    sleep 10

    save_kubeconfig

    puts "...k3s has been deployed to first master #{first_master.name} and the control plane is up."
  end

  private def set_up_other_masters
    channel = Channel(Hetzner::Server).new
    other_masters = masters[1..-1]

    other_masters.each do |master|
      spawn do
        puts "Deploying k3s to master #{master.name}..."

        ssh.run(master, master_install_script(master))

        puts "...k3s has been deployed to master #{master.name}."

        channel.send(master)
      end
    end

    other_masters.size.times do
      channel.receive
    end
  end

  private def set_up_workers
    channel = Channel(Hetzner::Server).new

    workers.each do |worker|
      spawn do
        puts "Deploying k3s to worker #{worker.name}..."

        ssh.run(worker, worker_install_script(worker))

        puts "...k3s has been deployed to worker #{worker.name}."

        channel.send(worker)
      end
    end

    workers.size.times do
      channel.receive
    end
  end

  private def master_install_script(master)
    server = master == first_master ? " --cluster-init " : " --server https://#{api_server_ip_address}:6443 "
    flannel_interface = find_flannel_interface(master)
    flannel_wireguard = find_flannel_wireguard
    extra_args = "#{kube_api_server_args_list} #{kube_scheduler_args_list} #{kube_controller_manager_args_list} #{kube_cloud_controller_manager_args_list} #{kubelet_args_list} #{kube_proxy_args_list}"
    taint = settings.schedule_workloads_on_masters ? " " : " --node-taint CriticalAddonsOnly=true:NoExecute "

    <<-SCRIPT
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="#{settings.k3s_version}" K3S_TOKEN="#{k3s_token}" INSTALL_K3S_EXEC="server \
      --disable-cloud-controller \
      --disable servicelb \
      --disable traefik \
      --disable local-storage \
      --disable metrics-server \
      --write-kubeconfig-mode=644 \
      --node-name="$(hostname -f)" \
      --cluster-cidr=10.244.0.0/16 \
      --etcd-expose-metrics=true \
      #{flannel_wireguard} \
      --kube-controller-manager-arg="bind-address=0.0.0.0" \
      --kube-proxy-arg="metrics-bind-address=0.0.0.0" \
      --kube-scheduler-arg="bind-address=0.0.0.0" \
      #{taint} #{extra_args} \
      --kubelet-arg="cloud-provider=external" \
      --advertise-address=$(hostname -I | awk '{print $2}') \
      --node-ip=$(hostname -I | awk '{print $2}') \
      --node-external-ip=$(hostname -I | awk '{print $1}') \
      --flannel-iface=#{flannel_interface} \
      #{server} #{tls_sans}" sh -
    SCRIPT
  end

  private def worker_install_script(worker)
    flannel_interface = find_flannel_interface(worker)

    <<-BASH
    curl -sfL https://get.k3s.io | K3S_TOKEN="#{k3s_token}" INSTALL_K3S_VERSION="#{settings.k3s_version}" K3S_URL=https://#{first_master.private_ip_address}:6443 INSTALL_K3S_EXEC="agent \
      --node-name="$(hostname -f)" \
      --kubelet-arg="cloud-provider=external" \
      --node-ip=$(hostname -I | awk '{print $2}') \
      --node-external-ip=$(hostname -I | awk '{print $1}') \
      --flannel-iface=#{flannel_interface}" sh -
    BASH
  end

  private def find_flannel_interface(server)
    if /Intel/ =~ ssh.run(server, "lscpu | grep Vendor", print_output: false)
      "ens10"
    else
      "enp7s0"
    end
  end

  private def find_flannel_wireguard
    if configuration.settings.enable_encryption
      available_releases = K3s.available_releases
      selected_k3s_index : Int32 = available_releases.index(settings.k3s_version).not_nil!
      k3s_1_23_6_index : Int32 = available_releases.index("v1.23.6+k3s1").not_nil!

      if selected_k3s_index >= k3s_1_23_6_index
        " --flannel-backend=wireguard-native "
      else
        " --flannel-backend=wireguard "
      end
    else
      " "
    end
  end

  private def kube_api_server_args_list
    settings.kube_api_server_args.map do |arg|
      " --kube-apiserver-arg=\"#{arg}\" "
    end.join
  end

  private def kube_scheduler_args_list
    settings.kube_scheduler_args.map do |arg|
      " --kube-scheduler-arg=\"#{arg}\" "
    end.join
  end

  private def kube_controller_manager_args_list
    settings.kube_controller_manager_args.map do |arg|
      " --kube-controller-manager-arg=\"#{arg}\" "
    end.join
  end

  private def kube_cloud_controller_manager_args_list
    settings.kube_cloud_controller_manager_args.map do |arg|
      " --kube-cloud-controller-manager-arg=\"#{arg}\" "
    end.join
  end

  private def kubelet_args_list
    settings.kubelet_args.map do |arg|
      " --kubelet-arg=\"#{arg}\" "
    end.join
  end

  private def kube_proxy_args_list
    settings.kube_proxy_args.map do |arg|
      " --kube-proxy-arg=\"#{arg}\" "
    end.join
  end

  private def k3s_token
    token = ssh.run(first_master, "{ TOKEN=$(< /var/lib/rancher/k3s/server/node-token); } 2> /dev/null; echo $TOKEN", print_output: false)

    if token.empty?
      Random::Secure.hex
    else
      token.split(':').last
    end
  end

  private def save_kubeconfig
    kubeconfig_path = settings.kubeconfig_path

    puts "Saving the kubeconfig file to #{kubeconfig_path}..."

    kubeconfig = ssh.run(first_master, "cat /etc/rancher/k3s/k3s.yaml", print_output: false).
      gsub("127.0.0.1", api_server_ip_address).
      gsub("default", settings.cluster_name)

    File.write(settings.kubeconfig_path, kubeconfig)

    File.chmod kubeconfig_path, 0o600
  end

  private def deploy_cloud_controller_manager
    puts check_kubectl

    puts "Deploying Hetzner Cloud Controller Manager..."

    command = <<-BASH
    kubectl apply -f - <<-EOF
      apiVersion: "v1"
      kind: "Secret"
      metadata:
        namespace: 'kube-system'
        name: 'hcloud'
      stringData:
        network: "#{settings.existing_network || settings.cluster_name}"
        token: "#{settings.hetzner_token}"
    EOF
    BASH

    status, result = Util::Shell.run(command, settings.kubeconfig_path)

    command = "kubectl apply -f https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/latest/download/ccm-networks.yaml"

    status, result = Util::Shell.run(command, settings.kubeconfig_path)

    puts "...Cloud Controller Manager deployed"
  end

  private def check_kubectl
    return if Util.which("kubectl")

    puts "Please ensure kubectl is installed and in your PATH."
    exit 1
  end
end
