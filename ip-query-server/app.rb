require 'sinatra'
require 'json'
require 'net/http'
require 'uri'
require 'time'

class HetznerApp < Sinatra::Base
  # Configuration
  configure do
    set :cache_duration, 30 # seconds
    set :per_page, 50 # Number of servers/load balancers to fetch per page
    set :host_authorization, { permitted_hosts: [] }
    set :valid_roles, ['master', 'worker', 'loadbalancer']
  end

  # Cache storage
  @@ip_cache = {}
  @@last_fetch_time = {}

  # Before filter to check for token and set content type
  before do
    content_type :json

    pass if request.path_info == "/health"

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

  get "/health" do
    "OK"
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

  def fetch_hetzner_page(token, page, resource_type = 'servers')
    uri = URI.parse("https://api.hetzner.cloud/v1/#{resource_type}?page=#{page}&per_page=#{settings.per_page}")
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

  def fetch_load_balancer_ips(token, master_server_ids)
    lb_ips = []
    page = 1

    # Fetch first page
    first_page_data = fetch_hetzner_page(token, page, 'load_balancers')
    return [] if error?(first_page_data) || !first_page_data['load_balancers']

    # Extract IPs only from LBs that target master nodes
    # This filters out Istio ingress LBs and other unrelated load balancers
    first_page_data['load_balancers'].each do |lb|
      if lb_targets_masters?(lb, master_server_ids) && lb['public_net'] && lb['public_net']['ipv4'] && lb['public_net']['ipv4']['ip']
        lb_ips << lb['public_net']['ipv4']['ip']
      end
    end

    # Calculate total pages
    meta = first_page_data['meta']
    total_pages = if meta && meta['pagination']
      (meta['pagination']['total_entries'].to_f / settings.per_page).ceil
    else
      1
    end

    # Fetch remaining pages if any
    (2..total_pages).each do |current_page|
      page_data = fetch_hetzner_page(token, current_page, 'load_balancers')
      next if error?(page_data) || !page_data['load_balancers']

      page_data['load_balancers'].each do |lb|
        if lb_targets_masters?(lb, master_server_ids) && lb['public_net'] && lb['public_net']['ipv4'] && lb['public_net']['ipv4']['ip']
          lb_ips << lb['public_net']['ipv4']['ip']
        end
      end
    end

    lb_ips
  end

  # Check if a load balancer targets any master nodes
  def lb_targets_masters?(lb, master_server_ids)
    return false if master_server_ids.empty?
    return false unless lb['targets']

    lb['targets'].any? do |target|
      if target['type'] == 'server' && target['server']
        master_server_ids.include?(target['server']['id'])
      elsif target['type'] == 'label_selector'
        # Label selector targeting masters (e.g., role=master)
        target['label_selector'] && target['label_selector']['selector'] =~ /role=master/
      else
        false
      end
    end
  end

  def fetch_and_cache_all_ips(token)
    # Initialize IP collections for all categories
    all_ips = []
    master_ips = []
    worker_ips = []
    master_server_ids = []
    lb_ips = []
    page = 1

    # Fetch first page to get pagination info
    first_page_data = fetch_hetzner_page(token, page)
    return first_page_data if error?(first_page_data)

    # Extract IPs from first page
    extract_and_categorize_ips(first_page_data, all_ips, master_ips, worker_ips, master_server_ids)

    # Calculate total pages
    total_pages = calculate_total_pages(first_page_data)

    # Fetch remaining pages if any
    (2..total_pages).each do |current_page|
      page_data = fetch_hetzner_page(token, current_page)
      return page_data if error?(page_data)
      extract_and_categorize_ips(page_data, all_ips, master_ips, worker_ips, master_server_ids)
    end

    # Also fetch load balancer IPs that target master nodes and add them to all_ips
    # This is critical for LB health checks when use_local_firewall: true
    lb_ips = fetch_load_balancer_ips(token, master_server_ids)
    all_ips.concat(lb_ips)

    # Update cache for all sets (including loadbalancer)
    update_cache(token, all_ips, master_ips, worker_ips, lb_ips)

    # Return the complete set of IPs
    all_ips
  end

  def extract_and_categorize_ips(page_data, all_ips, master_ips, worker_ips, master_server_ids)
    page_data['servers'].each do |server|
      ip = server['public_net']['ipv4']['ip']
      all_ips << ip

      # Also add to role-specific collections
      if server['labels'] && server['labels']['role'] == 'master'
        master_ips << ip
        master_server_ids << server['id']
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

  def update_cache(token, all_ips, master_ips, worker_ips, lb_ips = [])
    # Cache each set with its own key
    @@ip_cache["#{token}:all"] = all_ips
    @@ip_cache["#{token}:master"] = master_ips
    @@ip_cache["#{token}:worker"] = worker_ips
    @@ip_cache["#{token}:loadbalancer"] = lb_ips

    # Use a single last fetch time for the token
    @@last_fetch_time[token] = Time.now
  end
end
