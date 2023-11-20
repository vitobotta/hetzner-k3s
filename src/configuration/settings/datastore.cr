class Configuration::Settings::Datastore
  getter errors : Array(String)
  getter datastore : Configuration::Datastore

  def initialize(@errors, @datastore)
  end

  def validate
    case datastore.mode
    when "etcd"
    when "external"
      errors << "external_datastore_endpoint is required for external datastore" if datastore.external_datastore_endpoint.strip.empty?
    else
      errors << "datastore mode is invalid - allowed values are 'etcd' and 'external'"
    end
  end
end
