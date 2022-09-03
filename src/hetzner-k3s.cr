require "option_parser"

require "./k3s/configuration"

module Hetzner::K3s
  class CLI
    VERSION = "0.6.5"

    property command = :none
    property configuration_file_path = ""
    property new_k3s_version =" "
    property parser = OptionParser.new

    def start
      self.parser = OptionParser.parse do |parser|
        parser.banner = "Usage: hetzner-k3s [command] [arguments]"

        parser.on("create", "Create a cluster") do
          self.command = :create

          parser.banner = "Usage: hetzner-k3s create [arguments]"

          parser.on("-c CONFIG_FILE", "--config=CONFIG_FILE", "Specify the name to salute") { |_configuration_file_path| self.configuration_file_path = _configuration_file_path }

          parser.invalid_option do |flag|
            STDERR.puts "ERROR: #{flag} is not a valid option."
            STDERR.puts parser
            exit(1)
          end
        end

        parser.on("delete", "Delete a cluster") do
          self.command = :delete

          parser.banner = "Usage: hetzner-k3s delete [arguments]"

          parser.on("-c CONFIG_FILE", "--config=CONFIG_FILE", "Specify the name to salute") { |_configuration_file_path| self.configuration_file_path = _configuration_file_path }

          parser.invalid_option do |flag|
            STDERR.puts "ERROR: #{flag} is not a valid option."
            STDERR.puts parser
            exit(1)
          end
        end

        parser.on("upgrade", "Upgrade a cluster") do
          self.command = :upgrade

          parser.banner = "Usage: hetzner-k3s upgrade [arguments]"

          parser.on("-c CONFIG_FILE", "--config=CONFIG_FILE", "Specify the name to salute") { |_configuration_file_path| self.configuration_file_path = _configuration_file_path }

          parser.on("--version=VERSION", "Specify the new version of k3s") { |_new_k3s_version| self.new_k3s_version = _new_k3s_version }

          parser.invalid_option do |flag|
            STDERR.puts "ERROR: #{flag} is not a valid option."
            STDERR.puts parser
            exit(1)
          end
        end

        parser.on("-h", "--help", "Show this help") do
          puts parser
          exit
        end

        parser.invalid_option do |command|
          STDERR.puts "ERROR: #{command} is not a valid command."
          STDERR.puts parser
          exit(1)
        end
      end

      case command
      when :create
        puts "creating"
        configuration
        # create_cluster(configuration_file_path)
      when :delete
        puts "deleting"
        # delete_cluster(configuration_file_path)
      when :upgrade
        puts "upgrading"
      end
    end

    def configuration
      @configuration ||= Configuration.new(configuration_file_path: configuration_file_path)
    end
  end
end

Hetzner::K3s::CLI.new.start

