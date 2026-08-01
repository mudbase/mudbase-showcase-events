# frozen_string_literal: true

require "json"
require "mudbase_sdk"
require_relative "client_factory"
require_relative "config"
require_relative "errors"

module Mudbase
  # Thin repository over `events` - read granted to both roles (organizer/attendee), create
  # granted to organizer only, update/delete organizer-only AND scoped to the organizer's own
  # event by this app's own gate (see lib/session_helpers.rb#require_event_owner!;
  # plan/build-plan.md "RBAC Matrix"). All calls force `debug_return_type: "Object"` (see
  # ClientFactory) so every real document field survives typed deserialization.
  module EventsRepo
    # Real platform ceiling on the generated SDK's `DataApi#list_data` (`limit <= 100`,
    # confirmed live by the sibling kanban/social ports' own builds) - plenty for a demo-scale
    # event list; pagination (`page`) is used on top of it for the "/" event list.
    LIST_LIMIT = 100

    # @return [Hash] `{data: [...], pagination: {page:, limit:, total:, totalPages:, hasMore:}}` -
    #   a page of events, ascending by `startsAt` (soonest first), mirroring the reference web
    #   app's `useEvents(page)`.
    def self.page(access_token:, page:, limit: LIST_LIMIT)
      opts = { sort: "startsAt", page: page, limit: limit }.merge(Mudbase::ClientFactory::OBJECT_RESPONSE)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).list_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.events_collection_id,
        opts,
      )
      { events: data[:data] || [], pagination: data[:pagination] || {} }
    end

    def self.find(access_token:, id:)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).get_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.events_collection_id,
        id,
        Mudbase::ClientFactory::OBJECT_RESPONSE,
      )
      data[:data]
    rescue MudbaseSDK::ApiError => e
      raise e unless Mudbase::ApiFailure.from(e).status == 404

      nil
    end

    def self.create!(access_token:, attributes:)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).create_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.events_collection_id,
        attributes,
        Mudbase::ClientFactory::OBJECT_RESPONSE,
      )
      data[:data]
    end

    def self.update!(access_token:, id:, attributes:)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).update_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.events_collection_id,
        id,
        attributes,
        Mudbase::ClientFactory::OBJECT_RESPONSE,
      )
      data[:data]
    end

    def self.delete!(access_token:, id:)
      Mudbase::ClientFactory.data_api(access_token: access_token).delete_data(
        Mudbase::Config.project_id,
        Mudbase::Config.events_collection_id,
        id,
      )
    end
  end
end
