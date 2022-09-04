require "./configuration/node_pool"

class InstanceGroup
  getter group : Configuration::NodePool | Nil
  getter group_type : String
  getter workers : Bool = true
  getter masters : Bool = true
  getter errors : Array(String) = [] of String
  getter server_types : Array(String) = [] of String
  getter locations : Array(String) = [] of String
  getter masters_location : String | Nil

  def initialize(
        group : Configuration::NodePool | Nil,
        masters_location : String | Nil,
        type : Symbol = :workers,
        server_types : Array(String) = [] of String,
        locations : Array(String) = [] of String
      )

    @group = group
    @workers = type == :workers
    @masters = !@workers
    @group_type = workers ? "Worker mode pool '#{group_name}'" : "Masters pool"
    @server_types = server_types
    @locations = locations
    @masters_location = masters_location
  end

  def validate
    validate_group_name
    validate_instance_type
    validate_location
    validate_instance_count
    validate_marks "label"
    validate_marks "taint"

    errors
  end

  private def group_name : String
    @group_name ||= if group.nil?
      if workers
        "<unnamed-group>"
      else
        "masters"
      end
    elsif workers
      name = group.not_nil!.name

      if name.nil?
        "<unnamed-group>"
      else
        name
      end
    else
      "masters"
    end
  end

  private def validate_group_name
    return if masters || group_name =~ /\A([A-Za-z0-9\-_]+)\Z/

    @errors << "#{group_type} has an invalid name"
  end

  private def validate_instance_type
    instance_type = group.try &.instance_type

    if instance_type.nil?
      @errors << "#{group_type} has an invalid instance type"
    elsif !server_types.includes?(instance_type.not_nil!)
      @errors << "#{group_type} has an invalid instance type"
    end
  end

  private def validate_location
    location = group.try &.location

    if location.nil?
      @errors << "#{group_type} has an invalid location"
    else
      if locations.includes?(location)
        if workers && masters_location
          in_network_zone = masters_location == "ash" ? location == "ash" : location != "ash"

          unless in_network_zone
            @errors << "#{group_type} must be in the same network zone as the masters. If the masters are located in Ashburn, all the node pools must be located in Ashburn too, otherwise none of the node pools should be located in Ashburn."
          end
        end
      else
        @errors << "#{group_type} has an invalid location"
      end
    end
  end

  private def validate_instance_count
    instance_count = group.try &.instance_count

    if instance_count.nil?
    else
      instance_count = instance_count.not_nil!

      if instance_count < 1
        @errors << "#{group_type} must have at least one node"
      elsif instance_count > 10
        @errors << "#{group_type} cannot have more than 10 nodes due to a limitation with the Hetzner placement groups. You can add more node pools if you need more nodes."
      elsif !workers && !instance_count.odd?
        @errors << "Masters count must equal to 1 for non-HA clusters or an odd number (recommended 3) for an HA cluster"
      end
    end
  end

  private def validate_marks(type : String)
    marks = case type
    when "label"
      group.try &.labels
    when "taint"
      group.try &.taints
    end

    if marks
      marks.each do |label|
        if (label.key.nil? || label.value.nil?)
          @errors << "#{group_type} has an invalid #{type}"
          break
        end
      end
    end
  end
end
