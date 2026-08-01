# frozen_string_literal: true

require_relative "bookings_repo"
require_relative "activity_repo"

module Mudbase
  # Ports the reference Next.js app's `src/lib/capacity.ts` (`reconcileEventCapacity`) verbatim -
  # see plan/build-plan.md "Capacity-Race Handling Approach" for the full rationale. Mudbase (a
  # generic-CRUD BaaS) has no cross-document transactions or atomic counters, so a plain "count
  # confirmed, then create" is inherently racy: two simultaneous booking requests can both read
  # the same pre-write count and both decide "there's room". This module narrows that race window
  # by re-deriving truth from a fresh read after every booking create/cancel: creation-order
  # priority (the first `capacity` bookings, oldest first, among confirmed+waitlisted) are the
  # ones entitled to a seat; any booking whose current status disagrees with that derivation gets
  # corrected, with a matching `activity` entry logged for the correction.
  #
  # Deliberately excludes `"checked_in"` bookings from the capacity count (same reading of the
  # task's literal spec as the reference app) - capacity is defined in terms of `"confirmed"`
  # bookings specifically, and running this after check-in would incorrectly free an
  # already-seated attendee's slot for someone else on the waitlist.
  module Capacity
    def self.reconcile!(access_token:, event_id:, capacity:)
      live = Mudbase::BookingsRepo.live_for_event(access_token: access_token, event_id: event_id)

      live.each_with_index do |booking, index|
        should_be_confirmed = index < capacity

        if should_be_confirmed && booking[:status] != "confirmed"
          correct!(access_token, booking, "confirmed", "booking_promoted")
        elsif !should_be_confirmed && booking[:status] != "waitlisted"
          correct!(access_token, booking, "waitlisted", "booking_waitlisted")
        end
      end
    end

    def self.correct!(access_token, booking, new_status, action)
      Mudbase::BookingsRepo.update!(access_token: access_token, id: booking[:_id], attributes: { status: new_status })
      Mudbase::ActivityRepo.create!(
        access_token: access_token,
        attributes: {
          eventId: booking[:eventId],
          actorId: booking[:userId],
          actorName: booking[:userName],
          action: action,
        },
      )
    end
    private_class_method :correct!
  end
end
