require 'sinatra'
require 'json'
require 'net/http'
require 'uri'
require 'time'

class HetznerApp < Sinatra::Base
  # Configuration
  configure do
    set :cache_duration, 30 # seconds
    set :per_page, 50 # Number of servers to fetch per page
    set :host_authorization, { permitted_hosts: [] }
    set :valid_roles, ['master', 'worker']
  end

  # Cache storage
  @@ip_cache = {}
  @@last_fetch_time = {}

  # Before filter to check for token and set content type
  before do
    content_type :json
    halt 401, { error: 'Missing Hetzner API token' }.to_json unless token_present?
  end

  # Routes
  get '/ips' do
    role = params['role']
    # Only use valid roles
    role = nil unless settings.valid_roles.include?(role)

    # Check if we need to refresh the cache
    if !cache_valid?(token)
      # Fetch all servers and cache filtered results
      result = fetch_and_cache_all_ips(token)
      return error_response(result) if error?(result)
    end

    # Return the appropriate IP set from cache
    role_key = role || 'all'
    cache_key = "#{token}:#{role_key}"
    @@ip_cache[cache_key].to_json
  end

  delete '/cache' do
    # Clear all cache entries for this token
    token_prefix = "#{token}:"
    @@ip_cache.keys.select { |k| k.start_with?(token_prefix) }.each do |key|
      @@ip_cache.delete(key)
    end
    @@last_fetch_time.delete(token)
    { message: 'Cache cleared for this token' }.to_json
  end

  private

  # Helper methods
  def token
    request.env['HTTP_HETZNER_TOKEN']
  end

  def token_present?
    !token.nil? && !token.empty?
  end

  def cache_valid?(token)
    @@last_fetch_time[token] && (Time.now - @@last_fetch_time[token]) < settings.cache_duration
  end

  def error?(result)
    result.is_a?(Hash) && result[:error]
  end

  def error_response(result)
    status 500
    result.to_json
  end

  def fetch_hetzner_page(token, page)
    uri = URI.parse("https://api.hetzner.cloud/v1/servers?page=#{page}&per_page=#{settings.per_page}")
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{token}"
    request['Content-Type'] = 'application/json'

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if response.code == '200'
      JSON.parse(response.body)
    else
      { error: "Hetzner API error: #{response.code}", message: response.body }
    end
  end

  def fetch_and_cache_all_ips(token)
    # Initialize IP collections for all categories
    all_ips = []
    master_ips = []
    worker_ips = []
    page = 1

    # Fetch first page to get pagination info
    first_page_data = fetch_hetzner_page(token, page)
    return first_page_data if error?(first_page_data)

    # Extract IPs from first page
    extract_and_categorize_ips(first_page_data, all_ips, master_ips, worker_ips)

    # Calculate total pages
    total_pages = calculate_total_pages(first_page_data)

    # Fetch remaining pages if any
    (2..total_pages).each do |current_page|
      page_data = fetch_hetzner_page(token, current_page)
      return page_data if error?(page_data)
      extract_and_categorize_ips(page_data, all_ips, master_ips, worker_ips)
    end

    # Update cache for all three sets
    update_cache(token, all_ips, master_ips, worker_ips)

    # Return the complete set of IPs
    all_ips
  end

  def extract_and_categorize_ips(page_data, all_ips, master_ips, worker_ips)
    page_data['servers'].each do |server|
      ip = server['public_net']['ipv4']['ip']
      all_ips << ip

      # Also add to role-specific collections
      if server['labels'] && server['labels']['role'] == 'master'
        master_ips << ip
      elsif server['labels'] && server['labels']['role'] == 'worker'
        worker_ips << ip
      end
    end
  end

  def calculate_total_pages(page_data)
    meta = page_data['meta']
    if meta && meta['pagination']
      (meta['pagination']['total_entries'].to_f / settings.per_page).ceil
    else
      1
    end
  end

  def update_cache(token, all_ips, master_ips, worker_ips)
    # Cache each set with its own key
    @@ip_cache["#{token}:all"] = all_ips
    @@ip_cache["#{token}:master"] = master_ips
    @@ip_cache["#{token}:worker"] = worker_ips

    # Use a single last fetch time for the token
    @@last_fetch_time[token] = Time.now
  end
end
