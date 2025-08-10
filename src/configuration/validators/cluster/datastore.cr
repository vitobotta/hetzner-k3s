require "../../models/datastore"

class Configuration::Validators::Cluster::Datastore
  getter errors : Array(String)
  getter datastore : Configuration::Models::Datastore

  def initialize(@errors, @datastore)
  end

  def validate
    return errors << "datastore mode is invalid - allowed values are 'etcd' and 'external'" unless {"etcd", "external"}.includes?(datastore.mode)
    return unless datastore.mode == "external"

    errors << "external_datastore_endpoint is required for external datastore" if datastore.external_datastore_endpoint.strip.empty?
    
    datastore.etcd.validate_s3_settings(errors) if datastore.mode == "etcd"
    datastore.etcd.validate_etcd_settings(errors) if datastore.mode == "etcd"
  end
end