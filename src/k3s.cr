require "yaml"
require "file"
require "crest"

module K3s
  private GITHUB_DELIM_LINKS = ","
  private GITHUB_LINK_REGEX  = /<(?<link>[^>]+)>; rel="(?<rel>[^"]+)"/
  private RELEASES_DIRECTORY = File.expand_path("#{ENV["HOME"]}/.hetzner-k3s")
  private RELEASES_FILENAME  = File.expand_path("#{ENV["HOME"]}/.hetzner-k3s/k3s-releases.yaml")

  # Returns available K3s releases, cached for 7 days
  def self.available_releases
    Dir.mkdir(RELEASES_DIRECTORY) unless File.directory?(RELEASES_DIRECTORY)

    if File.exists?(RELEASES_FILENAME)
      file_age = Time.utc - File.info(RELEASES_FILENAME).modification_time
      return YAML.parse(File.read(RELEASES_FILENAME)).as_a if file_age <= 7.days

      # Delete expired cache
      File.delete(RELEASES_FILENAME)
    end

    releases = fetch_all_releases_from_github
    File.open(RELEASES_FILENAME, "w") { |f| YAML.dump(releases, f) }

    # Parse and return the cached file to ensure consistent return type
    YAML.parse(File.read(RELEASES_FILENAME)).as_a
  end

  # Fetches all K3s releases from GitHub API
  private def self.fetch_all_releases_from_github : Array(String)
    releases = [] of String
    next_page_url = "https://api.github.com/repos/k3s-io/k3s/tags?per_page=100"

    while next_page_url
      response = Crest.get(next_page_url, json: true)
      response_releases = JSON.parse(response.body).as_a
      releases.concat(response_releases.map { |release| release["name"].as_s })

      next_page_url = extract_next_github_page_url(response.headers["Link"]?)
    end

    releases.reverse
  end

  # Extracts the next page URL from GitHub's Link header
  private def self.extract_next_github_page_url(link_header : (Array(String) | String | Nil)) : String?
    return nil unless link_header

    header_string = link_header.is_a?(Array) ? link_header.join(GITHUB_DELIM_LINKS) : link_header
    links = header_string.split(GITHUB_DELIM_LINKS, remove_empty: true)

    links.each do |link|
      captures = GITHUB_LINK_REGEX.match(link.strip).try &.named_captures
      return captures["link"] if captures && captures["rel"]? == "next"
    end

    nil
  end

  # Retrieves the K3s token from master nodes
  def self.k3s_token(settings : Configuration::Main, masters : Array(Hetzner::Instance)) : String
    token_by_master(settings, masters) do |settings, master|
      begin
        ssh_client = ::Util::SSH.new(
          settings.networking.ssh.private_key_path,
          settings.networking.ssh.public_key_path
        )

        result = ssh_client.run(
          master,
          settings.networking.ssh.port,
          "cat /var/lib/rancher/k3s/server/node-token",
          settings.networking.ssh.use_agent,
          print_output: false
        )

        result.split(":").last
      rescue ex
        "" # Return empty string on any SSH error
      end
    end
  end

  # Gets token from master nodes, using quorum to determine the correct one
  def self.token_by_master(settings : Configuration::Main, masters : Array(Hetzner::Instance)) : String
    @@k3s_token ||= begin
      tokens = masters.map { |master| yield settings, master }.reject(&.empty?)

      if tokens.empty?
        Random::Secure.hex
      else
        # Find the most common token (quorum approach)
        token_counts = tokens.tally
        max_count = token_counts.max_of { |_, count| count }
        most_common_token = token_counts.key_for(max_count)

        # Return the token part after the last colon, or a new random token if empty
        most_common_token.empty? ? Random::Secure.hex : most_common_token.split(':').last
      end
    end
  end
end
