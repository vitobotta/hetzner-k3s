# frozen_string_literal: true

require 'thor'
require 'openssl'
require 'httparty'
require 'sshkey'
require 'ipaddr'
require 'open-uri'
require 'yaml'

require_relative 'cluster'
require_relative 'configuration'
require_relative 'version'

module Hetzner
  module K3s
    class CLI < Thor
      def self.exit_on_failure?
        true
      end

      desc 'version', 'Print the version'
      def version
        puts Hetzner::K3s::VERSION
      end

      desc 'create-cluster', 'Create a k3s cluster in Hetzner Cloud'
      option :config_file, required: true
      def create_cluster
        configuration.validate action: :create
        Cluster.new(configuration: configuration).create
      end

      desc 'delete-cluster', 'Delete an existing k3s cluster in Hetzner Cloud'
      option :config_file, required: true
      def delete_cluster
        configuration.validate action: :delete
        Cluster.new(configuration: configuration).delete
      end

      desc 'upgrade-cluster', 'Upgrade an existing k3s cluster in Hetzner Cloud to a new version'
      option :config_file, required: true
      option :new_k3s_version, required: true
      option :force, default: 'false'
      def upgrade_cluster
        configuration.validate action: :upgrade
        Cluster.new(configuration: configuration).upgrade(new_k3s_version: options[:new_k3s_version], config_file: options[:config_file])
      end

      desc 'releases', 'List available k3s releases'
      def releases
        Hetzner::Configuration.available_releases.each do |release|
          puts release
        end
      end

      private

      attr_reader :hetzner_token, :hetzner_client

      def configuration
        @configuration ||= begin
          config = ::Hetzner::Configuration.new(options: options)
          @hetzner_token = config.hetzner_token
          config
        end
      end
    end
  end
end
