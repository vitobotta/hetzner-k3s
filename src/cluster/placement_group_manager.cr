require "../hetzner/client"
require "../hetzner/placement_group/create"
require "../hetzner/placement_group/delete"

class Cluster::PlacementGroupManager
  MAX_SERVERS_PER_PLACEMENT_GROUP  = 10
  MAX_PLACEMENT_GROUPS_PER_PROJECT = 50

  struct PlacementGroups
    property masters : Array(Hetzner::PlacementGroup)
    property workers : Hash(String, Array(Hetzner::PlacementGroup))

    def initialize
      @masters = [] of Hetzner::PlacementGroup
      @workers = {} of String => Array(Hetzner::PlacementGroup)
    end
  end

  private getter settings : Configuration::Main
  private getter hetzner_client : Hetzner::Client
  private property groups_created : Int32 = 0

  def initialize(@settings, @hetzner_client)
  end

  def create(master_count : Int32, worker_node_pools : Array(Configuration::Models::WorkerNodePool)) : PlacementGroups
    result = PlacementGroups.new

    master_group_count = group_count_for(master_count)
    master_group_count.times do |i|
      group = create_or_find("#{settings.cluster_name}-masters-pg#{i + 1}", "masters", "")
      result.masters << group if group
    end

    worker_node_pools.each do |pool|
      pool_group_count = group_count_for(pool.instance_count)
      pool_name = pool.name || "default"
      pool_groups = [] of Hetzner::PlacementGroup

      pool_group_count.times do |i|
        group = create_or_find(
          "#{settings.cluster_name}-pool-#{pool_name}-workers-pg#{i + 1}",
          "workers",
          pool_name
        )
        pool_groups << group if group
      end

      result.workers[pool_name] = pool_groups
    end

    result
  end

  def delete
    success, response = hetzner_client.get("/placement_groups", {:label_selector => "cluster=#{settings.cluster_name}"})

    return unless success

    placement_groups = Hetzner::PlacementGroupsList.from_json(response).placement_groups

    placement_groups.each do |placement_group|
      Hetzner::PlacementGroup::Delete.new(
        hetzner_client: hetzner_client,
        placement_group_name: placement_group.name
      ).run
    end
  end

  private def group_count_for(instance_count : Int32) : Int32
    (instance_count.to_f / MAX_SERVERS_PER_PLACEMENT_GROUP).ceil.to_i.clamp(1, Int32::MAX)
  end

  private def create_or_find(name : String, role : String, pool : String) : Hetzner::PlacementGroup?
    return nil if groups_created >= MAX_PLACEMENT_GROUPS_PER_PROJECT

    labels = {
      "cluster" => settings.cluster_name,
      "role"    => role,
    }
    labels = labels.merge({"pool" => pool}) unless pool.empty?

    group = Hetzner::PlacementGroup::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      placement_group_name: name,
      labels: labels
    ).run

    self.groups_created += 1
    group
  end
end
