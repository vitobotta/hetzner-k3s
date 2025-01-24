require "yaml"

class Configuration::Datastore::S3
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
