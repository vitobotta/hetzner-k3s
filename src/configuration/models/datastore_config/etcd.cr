require "yaml"
require "uri"

class Configuration::Models::DatastoreConfig::Etcd
  include YAML::Serializable

  getter snapshot_retention : Int64 = 24
  getter snapshot_schedule_cron : String = "0.hourly"

  getter s3_enabled : Bool = false
  getter s3_endpoint : String = ""
  getter s3_region : String = ""
  getter s3_bucket : String = ""
  getter s3_folder : String = ""
  getter s3_access_key : String = ""
  getter s3_secret_key : String = ""
  getter s3_force_path_style : Bool = false

  def initialize(
    @snapshot_retention : Int64 = 24,
    @snapshot_schedule_cron : String = "0 * * * *",
    @s3_enabled : Bool = false,
    @s3_endpoint : String = "",
    @s3_region : String = "",
    @s3_bucket : String = "",
    @s3_folder : String = "",
    @s3_access_key : String = "",
    @s3_secret_key : String = "",
    @s3_force_path_style : Bool = false
  )
  end

  def s3_access_key_with_env_fallback : String
    s3_access_key.empty? ? ENV.fetch("ETCD_S3_ACCESS_KEY", "") : s3_access_key
  end

  def s3_secret_key_with_env_fallback : String
    s3_secret_key.empty? ? ENV.fetch("ETCD_S3_SECRET_KEY", "") : s3_secret_key
  end

  def s3_endpoint_with_env_fallback : String
    endpoint = s3_endpoint.empty? ? ENV.fetch("ETCD_S3_ENDPOINT", "") : s3_endpoint
    extract_hostname_from_url(endpoint)
  end

  private def extract_hostname_from_url(url : String) : String
    return url if url.empty?

    # Check if it's a full URL (contains ://)
    if url.includes?("://")
      begin
        uri = URI.parse(url)
        host = uri.host
        # Handle cases where host might be nil (invalid URL)
        return host || url
      rescue
        # If URL parsing fails, return original
        return url
      end
    end

    url
  end

  def s3_region_with_env_fallback : String
    s3_region.empty? ? ENV.fetch("ETCD_S3_REGION", "") : s3_region
  end

  def s3_bucket_with_env_fallback : String
    s3_bucket.empty? ? ENV.fetch("ETCD_S3_BUCKET", "") : s3_bucket
  end

  def s3_configured? : Bool
    return false unless s3_enabled

    endpoint = s3_endpoint_with_env_fallback
    bucket = s3_bucket_with_env_fallback
    access_key = s3_access_key_with_env_fallback
    secret_key = s3_secret_key_with_env_fallback

    !endpoint.empty? && !bucket.empty? && !access_key.empty? && !secret_key.empty?
  end

  def generate_etcd_args : String
    args = [] of String

    if snapshot_retention > 0
      args << "--etcd-snapshot-retention=#{snapshot_retention}"
    end

    unless snapshot_schedule_cron.empty?
      args << "--etcd-snapshot-schedule-cron='#{snapshot_schedule_cron}'"
    end

    if s3_configured?
      args << "--etcd-s3"
      args << "--etcd-s3-endpoint=#{s3_endpoint_with_env_fallback}"
      args << "--etcd-s3-region=#{s3_region_with_env_fallback}"
      args << "--etcd-s3-bucket=#{s3_bucket_with_env_fallback}"
      args << "--etcd-s3-access-key=#{s3_access_key_with_env_fallback}"
      args << "--etcd-s3-secret-key=#{s3_secret_key_with_env_fallback}"

      if s3_force_path_style
        args << "--etcd-s3-bucket-lookup-type=path"
      end

      unless s3_folder.empty?
        args << "--etcd-s3-folder=#{s3_folder}"
      end
    end

    args.join(" ")
  end
end
