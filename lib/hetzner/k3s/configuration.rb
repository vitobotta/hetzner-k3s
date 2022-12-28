# frozen_string_literal: true

module Hetzner


    def validate(action:)

      if valid_token?
        validate_cluster_name
        validate_kubeconfig_path

        case action
        when :create
          validate_create
        when :delete
          validate_kubeconfig_path_must_exist
        when :upgrade
          validate_upgrade
        end
      end

    end


    def validate_create
      validate_masters_location
      validate_masters
      validate_worker_node_pools
      validate_verify_host_key

      validate_additional_packages
      validate_post_create_commands
      validate_kube_api_server_args
      validate_kube_scheduler_args
      validate_kube_controller_manager_args
      validate_kube_cloud_controller_manager_args
      validate_kubelet_args
      validate_kube_proxy_args
      validate_existing_network
    end

    def validate_upgrade
      validate_kubeconfig_path_must_exist
      # validate_new_k3s_version
    end


    def validate_verify_host_key
      return unless [true, false].include?(configuration.fetch('public_ssh_key_path', false))

      errors << 'Please set the verify_host_key option to either true or false'
    end

    def validate_additional_packages
      additional_packages = configuration['additional_packages']
      errors << 'Invalid additional packages configuration - it should be an array' if additional_packages && !additional_packages.is_a?(Array)
    end

    def validate_post_create_commands
      post_create_commands = configuration['post_create_commands']
      errors << 'Invalid post create commands configuration - it should be an array' if post_create_commands && !post_create_commands.is_a?(Array)
    end

    def validate_kube_api_server_args
      kube_api_server_args = configuration['kube_api_server_args']
      return unless kube_api_server_args

      errors << 'kube_api_server_args must be an array of arguments' unless kube_api_server_args.is_a? Array
    end

    def validate_kube_scheduler_args
      kube_scheduler_args = configuration['kube_scheduler_args']
      return unless kube_scheduler_args

      errors << 'kube_scheduler_args must be an array of arguments' unless kube_scheduler_args.is_a? Array
    end

    def validate_kube_controller_manager_args
      kube_controller_manager_args = configuration['kube_controller_manager_args']
      return unless kube_controller_manager_args

      errors << 'kube_controller_manager_args must be an array of arguments' unless kube_controller_manager_args.is_a? Array
    end

    def validate_kube_cloud_controller_manager_args
      kube_cloud_controller_manager_args = configuration['kube_cloud_controller_manager_args']
      return unless kube_cloud_controller_manager_args

      errors << 'kube_cloud_controller_manager_args must be an array of arguments' unless kube_cloud_controller_manager_args.is_a? Array
    end

    def validate_kubelet_args
      kubelet_args = configuration['kubelet_args']
      return unless kubelet_args

      errors << 'kubelet_args must be an array of arguments' unless kubelet_args.is_a? Array
    end

    def validate_kube_proxy_args
      kube_proxy_args = configuration['kube_proxy_args']
      return unless kube_proxy_args

      errors << 'kube_proxy_args must be an array of arguments' unless kube_proxy_args.is_a? Array
    end

    def validate_configuration_file
      config_file_path = options[:config_file]

      if File.exist?(config_file_path)
        begin
          @configuration = YAML.load_file(options[:config_file])
          unless configuration.is_a? Hash
            puts 'Configuration is invalid'
            exit 1
          end
        rescue StandardError
          puts 'Please ensure that the config file is a correct YAML manifest.'
          exit 1
        end
      else
        puts 'Please specify a correct path for the config file.'
        exit 1
      end
    end

    def validate_token
      errors << 'Invalid Hetzner Cloud token' unless valid_token?
    end

    def validate_kubeconfig_path
      path = File.expand_path(configuration['kubeconfig_path'])
      errors << 'kubeconfig path cannot be a directory' and return if File.directory? path

      directory = File.dirname(path)
      errors << "Directory #{directory} doesn't exist" unless File.exist? directory
    rescue StandardError
      errors << 'Invalid path for the kubeconfig'
    end

    def validate_kubeconfig_path_must_exist
      path = File.expand_path configuration['kubeconfig_path']
      errors << 'kubeconfig path is invalid' and return unless File.exist? path

      errors << 'kubeconfig path cannot be a directory' if File.directory? path
    rescue StandardError
      errors << 'Invalid kubeconfig path'
    end

    def validate_cluster_name
      errors << 'Cluster name is an invalid format (only lowercase letters, digits and dashes are allowed)' unless configuration['cluster_name'] =~ /\A[a-z\d-]+\z/

      return if configuration['cluster_name'] =~ /\A[a-z]+.*([a-z]|\d)+\z/

      errors << 'Ensure that the cluster name starts and ends with a normal letter'
    end

    def validate_new_k3s_version
      new_k3s_version = options[:new_k3s_version]
      errors << 'The new k3s version is invalid' unless Hetzner::Configuration.available_releases.include? new_k3s_version
    end


    def validate_instance_group(instance_group, workers: true)
      instance_group_errors = []

      instance_group_type = workers ? "Worker mode pool '#{instance_group['name']}'" : 'Masters pool'

      instance_group_errors << "#{instance_group_type} has an invalid name" unless !workers || instance_group['name'] =~ /\A([A-Za-z0-9\-_]+)\Z/

      instance_group_errors << "#{instance_group_type} is in an invalid format" unless instance_group.is_a? Hash

      instance_group_errors << "#{instance_group_type} has an invalid instance type" unless !valid_token? || server_types.include?(instance_group['instance_type'])

      if workers
        location = instance_group.fetch('location', configuration['location'])
        instance_group_errors << "#{instance_group_type} has an invalid location - valid locations: nbg1 (Nuremberg, Germany), fsn1 (Falkenstein, Germany), hel1 (Helsinki, Finland) or ash (Ashburn, Virginia, USA)" unless valid_location?(location)

        in_network_zone = configuration['location'] == 'ash' ? location == 'ash' : location != 'ash'
        instance_group_errors << "#{instance_group_type} must be in the same network zone as the masters. If the masters are located in Ashburn, all the node pools must be located in Ashburn too, otherwise none of the node pools should be located in Ashburn." unless in_network_zone
      end

      if instance_group['instance_count'].is_a? Integer
        if instance_group['instance_count'] < 1
          instance_group_errors << "#{instance_group_type} must have at least one node"
        elsif instance_group['instance_count'] > 10
          instance_group_errors << "#{instance_group_type} cannot have more than 10 nodes due to a limitation with the Hetzner placement groups. You can add more node pools if you need more nodes."
        elsif !workers
          instance_group_errors << 'Masters count must equal to 1 for non-HA clusters or an odd number (recommended 3) for an HA cluster' unless instance_group['instance_count'].odd?
        end
      else
        instance_group_errors << "#{instance_group_type} has an invalid instance count"
      end

      instance_group_errors << "#{instance_group_type} has an invalid labels format - a hash is expected" if !instance_group['labels'].nil? && !instance_group['labels'].is_a?(Hash)
      instance_group_errors << "#{instance_group_type} has an invalid taints format - a hash is expected" if !instance_group['taints'].nil? && !instance_group['taints'].is_a?(Hash)

      errors << instance_group_errors
    end

    def valid_location?(location)
      return if locations.empty? && !valid_token?

      locations.include? location
    end

    def locations
      return [] unless valid_token?

      @locations ||= hetzner_client.get('/locations')['locations'].map { |location| location['name'] }
    rescue StandardError
      @errors << 'Cannot fetch locations with Hetzner API, please try again later'
      []
    end

    def schedule_workloads_on_masters?
      schedule_workloads_on_masters = configuration['schedule_workloads_on_masters']
      schedule_workloads_on_masters ? !!schedule_workloads_on_masters : false
    end

    def server_types
      return [] unless valid_token?

      @server_types ||= hetzner_client.get('/server_types')['server_types'].map { |server_type| server_type['name'] }
    rescue StandardError
      @errors << 'Cannot fetch server types with Hetzner API, please try again later'
      false
    end

    def validate_existing_network
      return unless configuration['existing_network']

      existing_network = Hetzner::Network.new(hetzner_client: hetzner_client, cluster_name: configuration['cluster_name'], existing_network: configuration['existing_network']).get

      return if existing_network

      @errors << "You have specified that you want to use the existing network named '#{configuration['existing_network']} but this network doesn't exist"
    end
  end
end
