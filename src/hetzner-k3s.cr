require "admiral"

require "./k3s/configuration"

module Hetzner::K3s
  class CLI < Admiral::Command
    VERSION = "0.6.5"

    class Create < Admiral::Command
      define_help description: "create - Create a cluster"

      define_flag configuration_file_path : String,
                  description: "The path of the YAML configuration file",
                  long: "config",
                  short: "c",
                  required: true

      def run
        configuration = Configuration.new(
          configuration_file_path: flags.configuration_file_path,
          command: :create
        )
      end
    end

    class Delete < Admiral::Command
      define_help description: "delete - Delete a cluster"

      define_flag configuration_file_path : String,
                  description: "The path of the YAML configuration file",
                  long: "config",
                  short: "c",
                  required: true

      def run
        puts "deleting"
        # configuration = Hetzner::K3s::Configuration.from_yaml(configuration_file_path)
        # puts configuration
      end
    end

    class Upgrade < Admiral::Command
      define_help description: "upgrade - Upgrade a cluster to a newer version of k3s"

      define_flag configuration_file_path : String,
                  description: "The path of the YAML configuration file",
                  long: "config",
                  short: "c",
                  required: true

      define_flag new_k3s_version : String,
                  description: "The new version of k3s to upgrade to",
                  long: "--k3s-version",
                  required: true

      def run
        puts "deleting"
        # configuration = Hetzner::K3s::Configuration.from_yaml(configuration_file_path)
        # puts configuration
      end
    end

    define_version VERSION

    define_help description: "hetzner-k3s - A tool to create k3s clusters on Hetzner Cloud"

    register_sub_command create : Create, description: "Create a cluster"
    register_sub_command delete : Delete, description: "Delete a cluster"
    register_sub_command upgrade : Upgrade, description: "Upgrade a cluster to a new version of k3s"

    def run
      puts help
    end
  end
end

Hetzner::K3s::CLI.run

