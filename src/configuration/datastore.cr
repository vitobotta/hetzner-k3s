require "yaml"

class Configuration::Datastore
  include YAML::Serializable

  getter mode : String = "etcd"
  getter external_datastore_endpoint : String = ""

  getter etcd : Etcd = Etcd.new

  def initialize(@mode : String = "etcd", @external_datastore_endpoint : String = "")
  end

  class Etcd
    include YAML::Serializable

    getter backups : Backups = Backups.new

    def initialize(@backups : Backups = Backups.new)
    end

    class Backups
      include YAML::Serializable

      getter enabled : Bool = true
      getter retention : Int32?
      getter dir : String?
      getter s3 : S3 = S3.new

      def initialize(@enabled : Bool = true, @s3 : S3 = S3.new)
      end

      class S3
        include YAML::Serializable

        getter enabled : Bool = false
        getter endpoint : String?
        getter endpoint_ca : String?
        getter skip_ssl_verify : Bool = false
        getter access_key : String = ""
        getter secret_key : String = ""
        getter bucket : String = ""
        getter region : String?
        getter folder : String?
        getter insecure : Bool = false
        getter timeout : String?

        def initialize(@enabled : Bool = false, @skip_ssl_verify : Bool = false, @access_key : String = "", @secret_key : String = "", @bucket : String = "", @insecure : Bool = false)
        end
      end
    end
  end
end
