# frozen_string_literal: true

module Hetzner
  class ConfigurationValidator
    def initialize(configuration:)
      @configuration = configuration
    end

    private

    attr_reader :configuration
  end
end
