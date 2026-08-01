# frozen_string_literal: true

module Mudbase
  # Fails fast at boot with a clear message rather than surfacing a confusing
  # nil-related error deep inside a request handler later.
  class MissingEnvError < StandardError
    def initialize(name)
      super("Missing required environment variable: #{name}")
    end
  end

  module Config
    def self.require_env(name)
      value = ENV[name]
      raise MissingEnvError, name if value.nil? || value.empty?

      value
    end

    def self.base_url
      ENV.fetch("MUDBASE_URL", "https://cloud.mudbase.dev")
    end

    def self.project_id
      require_env("MUDBASE_PROJECT_ID")
    end

    def self.events_collection_id
      require_env("EVENTS_COLLECTION_ID")
    end

    def self.bookings_collection_id
      require_env("BOOKINGS_COLLECTION_ID")
    end

    def self.activity_collection_id
      require_env("ACTIVITY_COLLECTION_ID")
    end

    def self.session_secret
      require_env("SESSION_SECRET")
    end
  end
end
