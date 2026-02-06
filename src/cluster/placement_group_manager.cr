require "../hetzner/placement_group/create"
require "../hetzner/placement_group/all"
require "../hetzner/placement_groups_list"

class Cluster::PlacementGroupManager
  MAX_PLACEMENT_GROUPS = 50
  MAX_INSTANCES_PER_PLACEMENT_GROUP = 9

  private getter settings : Configuration::Main
  private getter hetzner_client : Hetzner::Client
  private getter mutex : Mutex
  getter all_placement_groups : Array(Hetzner::PlacementGroup)

  def initialize(@settings, @hetzner_client, @mutex, @all_placement_groups)
    @placement_group_usage = Hash(String, Int32).new(0)
  end

  def find_by_name(placement_group_name)
    all_placement_groups.find { |pg| pg.name == placement_group_name }
  end

  def exists?(placement_group_name)
    find_by_name(placement_group_name)
  end

  def create_and_track(placement_group_name)
    Hetzner::PlacementGroup::Create.new(hetzner_client, placement_group_name).run.tap { |pg| track(pg) }
  end

  def create_for_masters
    placement_group_name = "#{settings.cluster_name}-masters"
    find_by_name(placement_group_name) || create_and_track(placement_group_name)
  end

  def create_for_node_pool(node_pool, remaining_placement_groups, placement_groups_channel)
    created_placement_groups = 0

    # Calculate exact number of placement groups needed
    # Hetzner placement groups have a strict limit of 10 instances per group
    needed_groups = (node_pool.instance_count + MAX_INSTANCES_PER_PLACEMENT_GROUP - 1) // MAX_INSTANCES_PER_PLACEMENT_GROUP
    placement_groups_count = [needed_groups, remaining_placement_groups].min

    # Get existing placement groups for this pool
    pool_placement_groups = all_placement_groups.select { |pg| pg.name.includes?("#{settings.cluster_name}-#{node_pool.name}-") }

    # Create missing placement groups starting from the next sequential index
    (1..placement_groups_count).each do |group_number|
      break if created_placement_groups >= remaining_placement_groups

      placement_group_name = "#{settings.cluster_name}-#{node_pool.name}-#{group_number}"
      next if exists?(placement_group_name)

      spawn do
        placement_group = create_and_track(placement_group_name)
        placement_groups_channel.send(placement_group)
      end

      created_placement_groups += 1
    end

    created_placement_groups
  end

  def create_for_worker_node_pools(node_pools)
    node_pools = node_pools.sort_by(&.name.not_nil!)

    remaining_placement_groups = MAX_PLACEMENT_GROUPS - all_placement_groups.size
    placement_groups_channel = Channel(Hetzner::PlacementGroup).new
    created_placement_groups = 0

    node_pools.each do |node_pool|
      next if node_pool.instance_count <= 0

      new_groups = create_for_node_pool(node_pool, remaining_placement_groups, placement_groups_channel)
      created_placement_groups += new_groups
      remaining_placement_groups -= new_groups

      break if remaining_placement_groups <= 0
    end

    created_placement_groups.times { placement_groups_channel.receive }
  end

  def delete_unused
    mutex.synchronize { @all_placement_groups = Hetzner::PlacementGroup::All.new(settings, hetzner_client).delete_unused }
  end

  def assign_placement_group(placement_groups, instance_index)
    mutex.synchronize do
      placement_groups.each { |pg| @placement_group_usage[pg.name] ||= 0 }

      available_groups = placement_groups.select { |pg| @placement_group_usage[pg.name] < MAX_INSTANCES_PER_PLACEMENT_GROUP }
      available_groups = placement_groups if available_groups.empty?

      target_group = available_groups.min_by { |pg| @placement_group_usage[pg.name] }
      @placement_group_usage[target_group.name] += 1
      target_group
    end
  end

  private def track(placement_group)
    mutex.synchronize { all_placement_groups << placement_group unless exists?(placement_group.name) }
    placement_group
  end
end
