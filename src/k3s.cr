require "yaml"
require "file"
require "crest"

module K3s
  private GITHUB_DELIM_LINKS = ","
  private GITHUB_LINK_REGEX  = /<(?<link>[^>]+)>; rel="(?<rel>[^"]+)"/
  private RELEASES_DIRECTORY = File.expand_path("#{ENV["HOME"]}/.hetzner-k3s")
  private RELEASES_FILENAME  = File.expand_path("#{ENV["HOME"]}/.hetzner-k3s/k3s-releases.yaml")

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
    releases
  end

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

  private def self.get_token_from_master(settings : Configuration::Main, master : Hetzner::Instance) : String?
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

      # Extract token part (after the last colon)
      result.split(":").last
    rescue ex
      nil # Return nil if we can't connect to the master
    end
  end

  def self.k3s_token(settings : Configuration::Main, masters : Array(Hetzner::Instance)) : String
    @@k3s_token ||= begin
      # Try to get token from each master node
      tokens = masters.compact_map { |master| get_token_from_master(settings, master) }

      # If we got tokens, return the most common one (quorum approach)
      unless tokens.empty?
        # Group tokens by value and count occurrences
        token_counts = tokens.tally
        # Find the token with the highest count
        most_frequent_token, _ = token_counts.max_by { |_, count| count }
        return most_frequent_token
      end

      # If no tokens found, generate a random one as fallback
      Random::Secure.hex
    end
  end
end
