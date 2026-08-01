# frozen_string_literal: true

require "json"
require "mudbase_sdk"
require_relative "client_factory"
require_relative "config"
require_relative "errors"

module Mudbase
  # Thin repository over `bookings`. Every write in this app is scoped to the signed-in user's
  # own booking (create a booking for yourself, cancel your own booking) - see
  # plan/build-plan.md "RBAC Matrix". All calls force `debug_return_type: "Object"` (see
  # ClientFactory) so every real document field (`eventId`, `userId`, `status`, `qrToken`, ...)
  # survives typed deserialization.
  module BookingsRepo
    # Real platform ceiling on the generated SDK's `DataApi#list_data` (`limit <= 100`,
    # confirmed live by the sibling kanban/social ports' own builds). See
    # plan/build-plan.md "Known Limitations" for what this means for capacity reconciliation on
    # an event whose live (confirmed+waitlisted) booking count exceeds 100.
    LIST_LIMIT = 100

    # A real server-side count (`pagination.total`), not a client-cached guess - the first half
    # of the capacity-race approach in plan/build-plan.md.
    def self.confirmed_count(access_token:, event_id:)
      opts = { filter: { eventId: event_id, status: "confirmed" }.to_json, limit: 1 }
        .merge(Mudbase::ClientFactory::OBJECT_RESPONSE)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).list_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.bookings_collection_id,
        opts,
      )
      (data[:pagination] || {})[:total].to_i
    end

    # Every confirmed-or-waitlisted (i.e. "live") booking for one event, oldest first - the set
    # the capacity reconciliation pass in `lib/mudbase/capacity.rb` re-derives truth from.
    def self.live_for_event(access_token:, event_id:)
      %w[confirmed waitlisted].flat_map do |status|
        opts = { filter: { eventId: event_id, status: status }.to_json, sort: "createdAt", limit: LIST_LIMIT }
          .merge(Mudbase::ClientFactory::OBJECT_RESPONSE)
        data, = Mudbase::ClientFactory.data_api(access_token: access_token).list_data_with_http_info(
          Mudbase::Config.project_id,
          Mudbase::Config.bookings_collection_id,
          opts,
        )
        data[:data] || []
      end.sort_by { |b| b[:createdAt].to_s }
    end

    # The signed-in user's own booking for one event, if any - used to hide the Book button /
    # show its current status instead (mirrors the reference web app's `useMyBookingForEvent`).
    def self.find_own(access_token:, event_id:, user_id:)
      opts = { filter: { eventId: event_id, userId: user_id }.to_json, limit: 1 }
        .merge(Mudbase::ClientFactory::OBJECT_RESPONSE)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).list_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.bookings_collection_id,
        opts,
      )
      (data[:data] || []).first
    end

    # Every booking the signed-in user has ever made, across all events, newest first - the
    # `/bookings` page.
    def self.for_user(access_token:, user_id:, limit: LIST_LIMIT)
      opts = { filter: { userId: user_id }.to_json, sort: "-createdAt", limit: limit }
        .merge(Mudbase::ClientFactory::OBJECT_RESPONSE)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).list_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.bookings_collection_id,
        opts,
      )
      data[:data] || []
    end

    # Looks up a booking within one event by its scanned/pasted `qrToken` - the check-in flow's
    # lookup step (`app/routes/events_routes.rb`).
    def self.find_by_qr_token(access_token:, event_id:, qr_token:)
      opts = { filter: { eventId: event_id, qrToken: qr_token }.to_json, limit: 1 }
        .merge(Mudbase::ClientFactory::OBJECT_RESPONSE)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).list_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.bookings_collection_id,
        opts,
      )
      (data[:data] || []).first
    end

    def self.find(access_token:, id:)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).get_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.bookings_collection_id,
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
        Mudbase::Config.bookings_collection_id,
        attributes,
        Mudbase::ClientFactory::OBJECT_RESPONSE,
      )
      data[:data]
    end

    def self.update!(access_token:, id:, attributes:)
      data, = Mudbase::ClientFactory.data_api(access_token: access_token).update_data_with_http_info(
        Mudbase::Config.project_id,
        Mudbase::Config.bookings_collection_id,
        id,
        attributes,
        Mudbase::ClientFactory::OBJECT_RESPONSE,
      )
      data[:data]
    end
  end
end
