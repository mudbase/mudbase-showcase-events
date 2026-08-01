# frozen_string_literal: true

require "json"
require "mudbase_sdk"
require_relative "client_factory"
require_relative "config"

module Mudbase
  # Thin repository over `activity` - one event's reverse-chronological history log. Read
  # granted to both roles; a row is only ever created as a side effect of a booking/check-in
  # action, never edited or deleted, so this module exposes no `update!`/`delete!`.
  module ActivityRepo
    # The event detail page shows the most recent 50 entries for that event, newest first -
    # matching the reference web app's `useEventActivity`.
    LIST_LIMIT = 50

    def self.for_event(access_token:, event_id:, limit: LIST_LIMIT)
      opts = { filter: { eventId: event_id }.to_json, sort: "-createdAt", limit: limit }
        .merge(Mudbase::ClientFactory::OBJECT_RESPONSE)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).list_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.activity_collection_id,
        opts,
      )
      data[:data] || []
    end

    def self.create!(access_token:, attributes:)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).create_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.activity_collection_id,
        attributes,
        Mudbase::ClientFactory::OBJECT_RESPONSE,
      )
      data[:data]
    end
  end
end
