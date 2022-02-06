# frozen_string_literal: true

module Hetzner
  class PlacementGroup
    def initialize(hetzner_client:, cluster_name:, pool_name: nil)
      @hetzner_client = hetzner_client
      @cluster_name = cluster_name
      @placement_group_name = pool_name ? "#{cluster_name}-#{pool_name}" : cluster_name
    end

    def create
      puts

      if (placement_group = find_placement_group)
        puts "Placement group #{placement_group_name} already exists, skipping."
        puts
        return placement_group['id']
      end

      puts "Creating placement group #{placement_group_name}..."

      response = hetzner_client.post('/placement_groups', placement_group_config).body

      puts "...placement group #{placement_group_name} created."
      puts

      JSON.parse(response)['placement_group']['id']
    end

    def delete
      if (placement_group = find_placement_group)
        puts "Deleting placement group #{placement_group_name}..."
        hetzner_client.delete('/placement_groups', placement_group['id'])
        puts "...placement group #{placement_group_name} deleted."
      else
        puts "Placement group #{placement_group_name} no longer exists, skipping."
      end

      puts
    end

    private

    attr_reader :hetzner_client, :cluster_name, :placement_group_name

    def placement_group_config
      {
        name: placement_group_name,
        type: 'spread'
      }
    end

    def find_placement_group
      hetzner_client.get('/placement_groups')['placement_groups'].detect do |placement_group|
        placement_group['name'] == placement_group_name
      end
    end
  end
end
