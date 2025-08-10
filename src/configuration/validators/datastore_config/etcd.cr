class Configuration::Validators::DatastoreConfig::Etcd
  getter errors : Array(String)
  getter etcd : Configuration::Models::DatastoreConfig::Etcd

  def initialize(@errors, @etcd)
  end

  def validate_s3_settings(path_prefix : String = "datastore.etcd") : Bool
    return true unless etcd.s3_enabled

    endpoint = etcd.s3_endpoint_with_env_fallback
    bucket = etcd.s3_bucket_with_env_fallback
    access_key = etcd.s3_access_key_with_env_fallback
    secret_key = etcd.s3_secret_key_with_env_fallback

    errors << "#{path_prefix}.s3_endpoint is required when etcd S3 snapshots are enabled" if endpoint.empty?
    errors << "#{path_prefix}.s3_bucket is required when etcd S3 snapshots are enabled" if bucket.empty?
    errors << "#{path_prefix}.s3_access_key is required when etcd S3 snapshots are enabled" if access_key.empty?
    errors << "#{path_prefix}.s3_secret_key is required when etcd S3 snapshots are enabled" if secret_key.empty?

    errors.empty?
  end

  def validate_etcd_settings(path_prefix : String = "datastore.etcd") : Bool
    if etcd.snapshot_retention < 0
      errors << "#{path_prefix}.snapshot_retention must be >= 0"
    end

    unless etcd.snapshot_schedule_cron.empty?
      if etcd.snapshot_schedule_cron.includes?(" ")
        cron_parts = etcd.snapshot_schedule_cron.split(' ')
        if cron_parts.size != 5
          errors << "#{path_prefix}.snapshot_schedule_cron must have exactly 5 fields when using cron format (minute hour day month weekday)"
        end
      end
    end

    errors.empty?
  end
end