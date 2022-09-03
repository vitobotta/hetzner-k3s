require "./k3s/cli"

module Hetzner::K3s
  VERSION = "0.6.5"

  def self.start
    command = nil
    configuration_file = nil
    new_k3s_version = nil

    parser = OptionParser.parse do |parser|
      parser.banner = "Usage: hetzner-k3s [command] [arguments]"

      parser.on("create", "Create a cluster") do
        command = :create

        parser.banner = "Usage: hetzner-k3s create [arguments]"

        parser.on("-c CONFIG_FILE", "--config=CONFIG_FILE", "Specify the name to salute") { |_configuration_file| configuration_file = _configuration_file }

        parser.invalid_option do |flag|
          STDERR.puts "ERROR: #{flag} is not a valid option."
          STDERR.puts parser
          exit(1)
        end
      end

      parser.on("delete", "Delete a cluster") do
        command = :delete

        parser.banner = "Usage: hetzner-k3s delete [arguments]"

        parser.on("-c CONFIG_FILE", "--config=CONFIG_FILE", "Specify the name to salute") { |_configuration_file| configuration_file = _configuration_file }

        parser.invalid_option do |flag|
          STDERR.puts "ERROR: #{flag} is not a valid option."
          STDERR.puts parser
          exit(1)
        end
      end

      parser.on("upgrade", "Upgrade a cluster") do
        command = :upgrade

        parser.banner = "Usage: hetzner-k3s upgrade [arguments]"

        parser.on("-c CONFIG_FILE", "--config=CONFIG_FILE", "Specify the name to salute") { |_configuration_file| configuration_file = _configuration_file }

        parser.on("--version=VERSION", "Specify the new version of k3s") { |_new_k3s_version| new_k3s_version = _new_k3s_version }

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
      # create_cluster(configuration_file)
    when :delete
      puts "deleting"
      # delete_cluster(configuration_file)
    when :upgrade
      puts "upgrading"
    end

    if configuration_file.nil?
      puts parser
      exit
    end
  end
end

Hetzner::K3s.start

