# frozen_string_literal: true

require 'thor'
require 'http'
require 'sshkey'
require 'ipaddr'
require 'open-uri'
require 'yaml'

require_relative 'cluster'
require_relative 'version'

module Hetzner
  module K3s
    class CLI < Thor
      def self.exit_on_failure?
        true
      end

      def initialize(*args)
        @errors = []

        super
      end

      desc 'version', 'Print the version'
      def version
        puts Hetzner::K3s::VERSION
      end

      desc 'create-cluster', 'Create a k3s cluster in Hetzner Cloud'
      option :config_file, required: true
      def create_cluster
        validate_configuration :create
        Cluster.new(hetzner_client:, hetzner_token:).create configuration:
      end

      desc 'delete-cluster', 'Delete an existing k3s cluster in Hetzner Cloud'
      option :config_file, required: true
      def delete_cluster
        validate_configuration :delete
        Cluster.new(hetzner_client:, hetzner_token:).delete configuration:
      end

      desc 'upgrade-cluster', 'Upgrade an existing k3s cluster in Hetzner Cloud to a new version'
      option :config_file, required: true
      option :new_k3s_version, required: true
      option :force, default: 'false'
      def upgrade_cluster
        validate_configuration :upgrade

        Cluster.new(hetzner_client:, hetzner_token:)
               .upgrade(configuration:, new_k3s_version: options[:new_k3s_version], config_file: options[:config_file])
      end

      desc 'releases', 'List available k3s releases'
      def releases
        available_releases.each do |release|
          puts release
        end
      end

      private

      attr_reader :configuration, :hetzner_client, :k3s_version
      attr_accessor :errors

      def validate_configuration(action)
        validate_configuration_file
        validate_token
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

        errors.flatten!

        return if errors.empty?

        puts 'Some information in the configuration file requires your attention:'

        errors.each do |error|
          puts " - #{error}"
        end

        exit 1
      end

      def valid_token?
        return @valid unless @valid.nil?

        begin
          token = hetzner_token
          @hetzner_client = Hetzner::Client.new(token:)
          response = hetzner_client.get('/locations')
          error_code = response.dig('error', 'code')
          @valid = error_code&.size != 0
        rescue StandardError
          @valid = false
        end
      end

      def validate_token
        errors << 'Invalid Hetzner Cloud token' unless valid_token?
      end

      def validate_cluster_name
        errors << 'Cluster name is an invalid format (only lowercase letters, digits and dashes are allowed)' unless configuration['cluster_name'] =~ /\A[a-z\d-]+\z/

        return if configuration['cluster_name'] =~ /\A[a-z]+.*\z/

        errors << 'Ensure that the cluster name starts with a normal letter'
      end

      def validate_kubeconfig_path
        path = File.expand_path(configuration['kubeconfig_path'])
        errors << 'kubeconfig path cannot be a directory' and return if File.directory? path

        directory = File.dirname(path)
        errors << "Directory #{directory} doesn't exist" unless File.exist? directory
      rescue StandardError
        errors << 'Invalid path for the kubeconfig'
      end

      def validate_public_ssh_key
        path = File.expand_path(configuration['public_ssh_key_path'])
        errors << 'Invalid Public SSH key path' and return unless File.exist? path

        key = File.read(path)
        errors << 'Public SSH key is invalid' unless ::SSHKey.valid_ssh_public_key?(key)
      rescue StandardError
        errors << 'Invalid Public SSH key path'
      end

      def validate_private_ssh_key
        private_ssh_key_path = configuration['private_ssh_key_path']

        return unless private_ssh_key_path

        path = File.expand_path(private_ssh_key_path)
        errors << 'Invalid Private SSH key path' and return unless File.exist?(path)
      rescue StandardError
        errors << 'Invalid Private SSH key path'
      end

      def validate_kubeconfig_path_must_exist
        path = File.expand_path configuration['kubeconfig_path']
        errors << 'kubeconfig path is invalid' and return unless File.exist? path

        errors << 'kubeconfig path cannot be a directory' if File.directory? path
      rescue StandardError
        errors << 'Invalid kubeconfig path'
      end

      def server_types
        return [] unless valid_token?

        @server_types ||= hetzner_client.get('/server_types')['server_types'].map { |server_type| server_type['name'] }
      rescue StandardError
        @errors << 'Cannot fetch server types with Hetzner API, please try again later'
        false
      end

      def locations
        return [] unless valid_token?

        @locations ||= hetzner_client.get('/locations')['locations'].map { |location| location['name'] }
      rescue StandardError
        @errors << 'Cannot fetch locations with Hetzner API, please try again later'
        []
      end

      def valid_location?(location)
        return if locations.empty? && !valid_token?

        locations.include? location
      end

      def validate_masters_location
        return if valid_location?(configuration['location'])

        errors << 'Invalid location for master nodes - valid locations: nbg1 (Nuremberg, Germany), fsn1 (Falkenstein, Germany), hel1 (Helsinki, Finland) or ash (Ashburn, Virginia, USA)'
      end

      def available_releases
        @available_releases ||= begin
          response = HTTP.get('https://api.github.com/repos/k3s-io/k3s/tags?per_page=999').body
          JSON.parse(response).map { |hash| hash['name'] }
        end
      rescue StandardError
        errors << 'Cannot fetch the releases with Hetzner API, please try again later'
      end

      def validate_k3s_version
        k3s_version = configuration['k3s_version']
        errors << 'Invalid k3s version' unless available_releases.include? k3s_version
      end

      def validate_new_k3s_version
        new_k3s_version = options[:new_k3s_version]
        errors << 'The new k3s version is invalid' unless available_releases.include? new_k3s_version
      end

      def validate_masters
        masters_pool = nil

        begin
          masters_pool = configuration['masters']
        rescue StandardError
          errors << 'Invalid masters configuration'
          return
        end

        if masters_pool.nil?
          errors << 'Invalid masters configuration'
          return
        end

        validate_instance_group masters_pool, workers: false
      end

      def validate_worker_node_pools
        worker_node_pools = configuration['worker_node_pools'] || []

        unless worker_node_pools.size.positive? || schedule_workloads_on_masters?
          errors << 'Invalid node pools configuration'
          return
        end

        return if worker_node_pools.size.zero? && schedule_workloads_on_masters?

        if !worker_node_pools.is_a? Array
          errors << 'Invalid node pools configuration'
        elsif worker_node_pools.size.zero?
          errors << 'At least one node pool is required in order to schedule workloads' unless schedule_workloads_on_masters?
        elsif worker_node_pools.map { |worker_node_pool| worker_node_pool['name'] }.uniq.size != worker_node_pools.size
          errors << 'Each node pool must have an unique name'
        elsif server_types
          worker_node_pools.each do |worker_node_pool|
            validate_instance_group worker_node_pool
          end
        end
      end

      def schedule_workloads_on_masters?
        schedule_workloads_on_masters = configuration['schedule_workloads_on_masters']
        schedule_workloads_on_masters ? !!schedule_workloads_on_masters : false
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

        errors << instance_group_errors
      end

      def validate_verify_host_key
        return unless [true, false].include?(configuration.fetch('public_ssh_key_path', false))

        errors << 'Please set the verify_host_key option to either true or false'
      end

      def hetzner_token
        @token = ENV.fetch('HCLOUD_TOKEN', nil)
        return @token unless @token.nil?

        @token = configuration['hetzner_token']
      end

      def validate_ssh_allowed_networks
        networks ||= configuration['ssh_allowed_networks']

        if networks.nil? || networks.empty?
          errors << 'At least one network/IP range must be specified for SSH access'
          return
        end

        invalid_networks = networks.reject do |network|
          IPAddr.new(network)
        rescue StandardError
          false
        end

        unless invalid_networks.empty?
          invalid_networks.each do |network|
            errors << "The network #{network} is an invalid range"
          end
        end

        invalid_ranges = networks.reject do |network|
          network.include? '/'
        end

        unless invalid_ranges.empty?
          invalid_ranges.each do |_network|
            errors << 'Please use the CIDR notation for the networks to avoid ambiguity'
          end
        end

        return unless invalid_networks.empty?

        current_ip = URI.open('http://whatismyip.akamai.com').read

        current_ip_networks = networks.detect do |network|
          IPAddr.new(network).include?(current_ip)
        rescue StandardError
          false
        end

        errors << "Your current IP #{current_ip} is not included into any of the networks you've specified, so we won't be able to SSH into the nodes" unless current_ip_networks
      end

      def validate_additional_packages
        additional_packages = configuration['additional_packages']
        errors << 'Invalid additional packages configuration - it should be an array' if additional_packages && !additional_packages.is_a?(Array)
      end

      def validate_post_create_commands
        post_create_commands = configuration['post_create_commands']
        errors << 'Invalid post create commands configuration - it should be an array' if post_create_commands && !post_create_commands.is_a?(Array)
      end

      def validate_create
        validate_public_ssh_key
        validate_private_ssh_key
        validate_ssh_allowed_networks
        validate_masters_location
        validate_k3s_version
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
      end

      def validate_upgrade
        validate_kubeconfig_path_must_exist
        validate_new_k3s_version
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
    end
  end
end
