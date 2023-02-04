require "yaml"
require "file"

module K3s
  GITHUB_DELIM_LINKS = ","
  GITHUB_LINK_REGEX = /<(?<link>[^>]+)>; rel="(?<rel>[^"]+)"/
  RELEASES_FILENAME = "/tmp/k3s-releases.yaml"

  def self.available_releases
    if File.exists?(RELEASES_FILENAME)
      YAML.parse(File.read(RELEASES_FILENAME)).as_a
    else
      response = Crest.get("https://api.github.com/repos/k3s-io/k3s/tags?per_page=100", json: true)
      releases = JSON.parse(response.body).as_a.map { |release| release["name"] }
      link_header = response.headers["Link"].to_s

      until link_header.nil?
        next_page_url = extract_next_github_page_url(link_header)

        break if next_page_url.nil?

        response = Crest.get(next_page_url, json: true)
        page_releases = JSON.parse(response.body).as_a.map { |release| release["name"] }

        releases += page_releases

        link_header = response.headers["Link"].to_s
      end

      releases = releases.to_a.map(&.to_s).reverse

      File.open(RELEASES_FILENAME, "w") { |f| YAML.dump(releases, f) }

      releases
    end
  end

  private def self.extract_next_github_page_url(link_header : (Array(String) | String)) : String | Nil
    links = link_header.split(GITHUB_DELIM_LINKS, remove_empty: true)

    links.each do |link|
      captures = GITHUB_LINK_REGEX.match(link.strip).try &.named_captures
      if captures && captures.has_key?("link") && captures.has_key?("rel") && captures["rel"] == "next"
        return captures["link"]
      end
    end

    nil
  end
end
