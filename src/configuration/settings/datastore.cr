class Configuration::Settings::Datastore
  getter errors : Array(String)
  getter datastore : Configuration::Datastore::Config

  def initialize(@errors, @datastore)
  end

  def validate
    case datastore.mode
    when "etcd"
      return unless datastore.etcd.backups.s3.enabled

      s3 = datastore.etcd.backups.s3
      errors << "access_key is required for S3 backups" if s3.access_key.strip.empty?
      errors << "secret_key is required for S3 backups" if s3.secret_key.strip.empty?
      errors << "bucket is required for S3 backups" if s3.bucket.strip.empty?
    when "external"
      errors << "external_datastore_endpoint is required for external datastore" if datastore.external_datastore_endpoint.strip.empty?
      errors << "etcd options cannot be set for external datastore" if datastore.etcd
    else
      errors << "datastore mode is invalid - allowed values are 'etcd' and 'external'"
    end
  end
end
