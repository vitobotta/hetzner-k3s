require "sinatra"
require "json"
require "net/http"
require "uri"
require "time"
require "concurrent"

class HetznerApp < Sinatra::Base
  configure do
    set :cache_duration, ENV.fetch("CACHE_DURATION", 30).to_i
    set :per_page, ENV.fetch("PER_PAGE", 50).to_i
    set :http_open_timeout, ENV.fetch("HTTP_OPEN_TIMEOUT", 5).to_i
    set :http_read_timeout, ENV.fetch("HTTP_READ_TIMEOUT", 10).to_i
    set :max_retries, ENV.fetch("MAX_RETRIES", 3).to_i
    set :retry_base_delay, ENV.fetch("RETRY_BASE_DELAY", 0.5).to_f
    set :valid_roles, %w[master worker loadbalancer]
  end

  CACHE = Concurrent::Map.new
  LAST_FETCH_TIME = Concurrent::Map.new
  CACHE_MUTEX = Mutex.new

  before do
    content_type :json
    pass if request.path_info == "/health"
    halt 401, { error: "Missing Hetzner API token" }.to_json unless token_present?
  end

  get "/ips" do
    role = params["role"]
    role = nil unless settings.valid_roles.include?(role)

    unless cache_valid?(token)
      result = fetch_and_cache_all_ips(token)
      return error_response(result) if error?(result)
    end

    cache_key = "#{token}:#{role || "all"}"
    CACHE[cache_key].to_json
  end

  get "/health" do
    "OK"
  end

  delete "/cache" do
    token_prefix = "#{token}:"
    CACHE_MUTEX.synchronize do
      CACHE.keys.select { |k| k.start_with?(token_prefix) }.each { |key| CACHE.delete(key) }
      LAST_FETCH_TIME.delete(token)
    end
    { message: "Cache cleared for this token" }.to_json
  end

  private

  def token
    request.env["HTTP_HETZNER_TOKEN"]
  end

  def token_present?
    !token.nil? && !token.empty?
  end

  def cache_valid?(token)
    last_fetch = LAST_FETCH_TIME[token]
    last_fetch && (Time.now - last_fetch) < settings.cache_duration
  end

  def error?(result)
    result.is_a?(Hash) && result[:error]
  end

  def error_response(result)
    status result[:status] || 500
    result.to_json
  end

  def with_retry(max_retries: settings.max_retries, base_delay: settings.retry_base_delay)
    retries = 0
    begin
      yield
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
           SocketError => e
      retries += 1
      if retries <= max_retries
        sleep(base_delay * (2**(retries - 1)))
        retry
      else
        { error: "Connection failed after #{max_retries} retries: #{e.message}", status: 503 }
      end
    rescue JSON::ParserError => e
      { error: "Invalid JSON response: #{e.message}", status: 502 }
    end
  end

  def fetch_hetzner_page(token, page, resource_type = "servers")
    uri = URI.parse("https://api.hetzner.cloud/v1/#{resource_type}?page=#{page}&per_page=#{settings.per_page}")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"

    with_retry do
      response = Net::HTTP.start(uri.hostname, uri.port,
                                 use_ssl: true,
                                 open_timeout: settings.http_open_timeout,
                                 read_timeout: settings.http_read_timeout) do |http|
        http.request(request)
      end

      if response.code == "200"
        JSON.parse(response.body)
      elsif response.code.to_i >= 500
        { error: "Hetzner API server error: #{response.code}", status: 502 }
      else
        { error: "Hetzner API error: #{response.code}", message: response.body, status: response.code.to_i }
      end
    end
  end

  def paginate_hetzner(token, resource_type)
    first_page = fetch_hetzner_page(token, 1, resource_type)
    return first_page if error?(first_page)

    yield first_page if block_given?

    total_pages = total_pages_from(first_page)
    (2..total_pages).each do |page|
      page_data = fetch_hetzner_page(token, page, resource_type)
      return page_data if error?(page_data)

      yield page_data if block_given?
    end

    nil
  end

  def total_pages_from(page_data)
    meta = page_data["meta"]
    return 1 unless meta && meta["pagination"]

    (meta["pagination"]["total_entries"].to_f / settings.per_page).ceil
  end

  def lb_ipv4(lb)
    lb.dig("public_net", "ipv4", "ip")
  end

  def fetch_load_balancer_ips(token, master_server_ids)
    return [] if master_server_ids.empty?

    lb_ips = []
    paginate_hetzner(token, "load_balancers") do |page_data|
      next unless page_data["load_balancers"]

      page_data["load_balancers"].each do |lb|
        ip = lb_ipv4(lb)
        lb_ips << ip if ip && lb_targets_masters?(lb, master_server_ids)
      end
    end

    lb_ips
  end

  def lb_targets_masters?(lb, master_server_ids)
    return false unless lb["targets"]

    lb["targets"].any? do |target|
      case target["type"]
      when "server" then target["server"] && master_server_ids.include?(target["server"]["id"])
      when "label_selector" then target.dig("label_selector", "selector")&.match?(/role=master/)
      else false
      end
    end
  end

  def fetch_and_cache_all_ips(token)
    all_ips = []
    master_ips = []
    worker_ips = []
    master_server_ids = []

    paginate_hetzner(token, "servers") do |page_data|
      next unless page_data["servers"]

      page_data["servers"].each do |server|
        ip = server.dig("public_net", "ipv4", "ip")
        next unless ip

        all_ips << ip
        role = server.dig("labels", "role")

        case role
        when "master"
          master_ips << ip
          master_server_ids << server["id"]
        when "worker"
          worker_ips << ip
        end
      end
    end

    lb_ips = fetch_load_balancer_ips(token, master_server_ids)
    all_ips.concat(lb_ips)

    update_cache(token, all_ips, master_ips, worker_ips, lb_ips)
    all_ips
  end

  def update_cache(token, all_ips, master_ips, worker_ips, lb_ips = [])
    CACHE_MUTEX.synchronize do
      CACHE["#{token}:all"] = all_ips
      CACHE["#{token}:master"] = master_ips
      CACHE["#{token}:worker"] = worker_ips
      CACHE["#{token}:loadbalancer"] = lb_ips
      LAST_FETCH_TIME[token] = Time.now
    end
  end
end
