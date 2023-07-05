require "../client"
require "./find"

class Hetzner::LoadBalancer::Create
  getter hetzner_client : Hetzner::Client
  getter cluster_name : String
  getter location : String
  getter network_id : Int64
  getter load_balancer_finder : Hetzner::LoadBalancer::Find
  getter load_balancer_name : String do
    "#{cluster_name}-api"
  end

  def initialize(@hetzner_client, @cluster_name, @location, @network_id)
    @load_balancer_finder = Hetzner::LoadBalancer::Find.new(@hetzner_client, load_balancer_name)
  end

  def run
    load_balancer = load_balancer_finder.run

    if load_balancer
      puts "Load balancer for API server already exists, skipping."
    else
      print "Creating load balancer for API server..."
      create_load_balancer
      load_balancer = wait_for_load_balancer_public_ip
      puts "done."
    end

    load_balancer.not_nil!
  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to create load balancer: #{ex.message}"
    STDERR.puts ex.response
    exit 1
  end

  private def create_load_balancer
    hetzner_client.post("/load_balancers", load_balancer_config)
  end

  private def wait_for_load_balancer_public_ip
    loop do
      load_balancer = load_balancer_finder.run
      break load_balancer if load_balancer.try(&.public_ip_address)
      sleep 1
    end
  end

  private def load_balancer_config
    {
      algorithm: {
        type: "round_robin"
      },
      load_balancer_type: "lb11",
      location: location,
      name: load_balancer_name,
      network: network_id,
      public_interface: true,
      services: [
        {
          destination_port: 6443,
          listen_port: 6443,
          protocol: "tcp",
          proxyprotocol: false
        }
      ],
      targets: [
        {
          label_selector: {
            selector: "cluster=#{cluster_name},role=master"
          },
          type: "label_selector",
          use_private_ip: true
        }
      ]
    }
  end
end
