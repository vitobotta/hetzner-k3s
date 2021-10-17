module Hetzner
  class SSHKey
    def initialize(hetzner_client:, cluster_name:)
      @hetzner_client = hetzner_client
      @cluster_name = cluster_name
    end

    def create(public_ssh_key_path:)
      @public_ssh_key_path = public_ssh_key_path

      puts

      if (public_ssh_key = find_public_ssh_key)
        puts "SSH key already exists, skipping."
        puts
        return public_ssh_key["id"]
      end

      puts "Creating SSH key..."

      response = hetzner_client.post("/ssh_keys", ssh_key_config).body

      puts "...SSH key created."
      puts

      JSON.parse(response)["ssh_key"]["id"]
    end

    def delete(public_ssh_key_path:)
      @public_ssh_key_path = public_ssh_key_path

      if (public_ssh_key = find_public_ssh_key)
        if public_ssh_key["name"] == cluster_name
          puts "Deleting ssh_key..."
          hetzner_client.delete("/ssh_keys", public_ssh_key["id"])
          puts "...ssh_key deleted."
        else
          puts "The SSH key existed before creating the cluster, so I won't delete it."
        end
      else
        puts "SSH key no longer exists, skipping."
      end

      puts
    end

    private

      attr_reader :hetzner_client, :cluster_name, :public_ssh_key_path

      def public_ssh_key
        @public_ssh_key ||= File.read(public_ssh_key_path).chop
      end

      def ssh_key_config
        {
          name: cluster_name,
          public_key: public_ssh_key
        }
      end

      def fingerprint
        @fingerprint ||= ::SSHKey.fingerprint(public_ssh_key)
      end

      def find_public_ssh_key
        key = hetzner_client.get("/ssh_keys")["ssh_keys"].detect do |ssh_key|
          ssh_key["fingerprint"] == fingerprint
        end

        unless key
          key = hetzner_client.get("/ssh_keys")["ssh_keys"].detect do |ssh_key|
            ssh_key["name"] == cluster_name
          end
        end

        key
      end

  end
end
