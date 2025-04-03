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
    if cache_valid?(token)
      @@ip_cache[token].to_json
    else
      result = fetch_hetzner_ips(token)
      return error_response(result) if error?(result)
      result.to_json
    end
  end

  delete '/cache' do
    @@ip_cache.delete(token)
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

  def fetch_hetzner_ips(token)
    all_ips = []
    page = 1

    # Fetch first page to get pagination info
    first_page_data = fetch_hetzner_page(token, page)
    return first_page_data if error?(first_page_data)

    # Extract IPs from first page
    extract_ips(first_page_data, all_ips)

    # Calculate total pages
    total_pages = calculate_total_pages(first_page_data)

    # Fetch remaining pages if any
    (2..total_pages).each do |current_page|
      page_data = fetch_hetzner_page(token, current_page)
      return page_data if error?(page_data)
      extract_ips(page_data, all_ips)
    end

    # Update cache for this specific token
    update_cache(token, all_ips)

    all_ips
  end

  def extract_ips(page_data, all_ips)
    page_data['servers'].each do |server|
      all_ips << server['public_net']['ipv4']['ip']
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

  def update_cache(token, ips)
    @@ip_cache[token] = ips
    @@last_fetch_time[token] = Time.now
  end
end
