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
    if load_balancer = load_balancer_finder.run
      puts "Load balancer for API server already exists, skipping."
    else
      print "Creating load balancer for API server..."

      hetzner_client.post("/load_balancers", load_balancer_config)
      load_balancer = load_balancer_finder.run

      while load_balancer.try(&.public_ip_address).nil?
        sleep 1
        load_balancer = load_balancer_finder.run
      end

      puts "done."
    end

    load_balancer.not_nil!

  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to create load balancer: #{ex.message}"
    STDERR.puts ex.response

    exit 1
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
