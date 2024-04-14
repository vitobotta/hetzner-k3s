# frozen_string_literal: true

require_relative "lib/hetzner/k3s/version"

Gem::Specification.new do |spec|
  spec.name = "hetzner-k3s"
  spec.version = Hetzner::K3s::VERSION
  spec.authors = ["Vito Botta"]

  spec.summary = "The easiest way to create production grade Kubernetes clusters in Hetzner Cloud"
  spec.description = "A CLI tool to create and manage Kubernetes clusters in Hetzner Cloud using the lightweight distribution k3s by Rancher."
  spec.homepage = "https://github.com/vitobotta/hetzner-k3s"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/vitobotta/hetzner-k3s"
  spec.metadata["changelog_uri"] = "https://github.com/vitobotta/hetzner-k3s/releases"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html

  spec.add_development_dependency  "rake", '~> 13.2', '>= 13.2.1'
  spec.add_development_dependency  "rspec", '~> 3.13'
  spec.add_development_dependency  "rubocop", '~> 1.63', '>= 1.63.1'
  spec.add_development_dependency "rubocop-rake", '~> 0.6.0'
  spec.add_development_dependency "rubocop-rspec", '~> 2.29', '>= 2.29.1'
end
