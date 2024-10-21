require "./s3"

class Configuration::Settings::Datastore
  getter errors : Array(String)
  getter datastore : Configuration::Datastore

  def initialize(@errors, @datastore)
  end

  def validate
    case datastore.mode
    when "etcd"
      Settings::S3.new(errors, datastore.s3).validate
    when "external"
      errors << "external_datastore_endpoint is required for external datastore" if datastore.external_datastore_endpoint.strip.empty?
      errors << "s3 backups is only availabe on 'etcd' datastore" if datastore.s3.enabled
    else
      errors << "datastore mode is invalid - allowed values are 'etcd' and 'external'"
    end
  end
end
