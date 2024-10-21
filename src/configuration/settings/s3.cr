class Configuration::Settings::S3
  getter errors : Array(String)
  getter s3 : Configuration::S3

  def initialize(@errors, @s3)
  end

  def validate
    case s3.enabled
    when true
      errors << "access_key is required for S3 backups" if s3.access_key.strip.empty?
      errors << "secret_key is required for S3 backups" if s3.secret_key.strip.empty?
      errors << "bucket is required for S3 backups" if s3.bucket.strip.empty?
    end
  end
end
