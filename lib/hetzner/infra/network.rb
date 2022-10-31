# frozen_string_literal: true

module Hetzner
  class Network
    def initialize(hetzner_client:, cluster_name:, existing_network:)
      @hetzner_client = hetzner_client
      @cluster_name = cluster_name
      @existing_network = existing_network
    end

    def create(location:)
      @location = location
      puts

      if (network = find_network)
        puts 'Private network already exists, skipping.'
        puts
        return network['id']
      end

      puts 'Creating private network...'

      response = hetzner_client.post('/networks', network_config).body

      puts '...private network created.'
      puts

      JSON.parse(response)['network']['id']
    end

    def delete
      if (network = find_network)
        if network['name'] == existing_network
          puts 'Network existed before cluster, skipping.'
        else
          puts 'Deleting network...'
          hetzner_client.delete('/networks', network['id'])
          puts '...network deleted.'
        end
      else
        puts 'Network no longer exists, skipping.'
      end

      puts
    end

    def find_network
      network_name = existing_network || cluster_name
      hetzner_client.get('/networks')['networks'].detect { |network| network['name'] == network_name }
    end

    def get
      find_network
    end

    private

    attr_reader :hetzner_client, :cluster_name, :location, :existing_network

    def network_config
      {
        name: cluster_name,
        ip_range: '10.0.0.0/16',
        subnets: [
          {
            ip_range: '10.0.0.0/24',
            network_zone: (location == 'ash' ? 'us-east' : 'eu-central'),
            type: 'cloud'
          }
        ]
      }
    end
  end
end
