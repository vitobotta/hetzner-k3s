# frozen_string_literal: true

module Hetzner
  class PlacementGroup
    def initialize(hetzner_client:, cluster_name:)
      @hetzner_client = hetzner_client
      @cluster_name = cluster_name
    end

    def create
      puts

      if (placement_group = find_placement_group)
        puts 'Placement group already exists, skipping.'
        puts
        return placement_group['id']
      end

      puts 'Creating placement group...'

      response = hetzner_client.post('/placement_groups', placement_group_config).body

      puts '...placement group created.'
      puts

      JSON.parse(response)['placement_group']['id']
    end

    def delete
      if (placement_group = find_placement_group)
        puts 'Deleting placement group...'
        hetzner_client.delete('/placement_groups', placement_group['id'])
        puts '...placement group deleted.'
      else
        puts 'Placement group no longer exists, skipping.'
      end

      puts
    end

    private

    attr_reader :hetzner_client, :cluster_name

    def placement_group_config
      {
        name: cluster_name,
        type: 'spread'
      }
    end

    def find_placement_group
      hetzner_client.get('/placement_groups')['placement_groups'].detect do |placement_group|
        placement_group['name'] == cluster_name
      end
    end
  end
end
