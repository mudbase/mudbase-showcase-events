# frozen_string_literal: true

# The signed-in user's own bookings across every event, plus cancellation. Every route here is
# scoped to the current user's own booking (`booking[:userId] == @current_user[:id]`) - checked
# by this app before any mutating Mudbase call, independent of Mudbase's own collection
# permissions underneath it (attendee: create/read/update own bookings only, per
# plan/build-plan.md "RBAC Matrix").
class App < Sinatra::Base
  get "/bookings" do
    require_login!

    @bookings = with_access_token { |token| Mudbase::BookingsRepo.for_user(access_token: token, user_id: @current_user[:id]) }

    events_by_id = {}
    with_access_token do |token|
      @bookings.each do |booking|
        event_id = booking[:eventId]
        next if events_by_id.key?(event_id)

        events_by_id[event_id] = Mudbase::EventsRepo.find(access_token: token, id: event_id)
      end
    end
    @events_by_id = events_by_id

    erb :"bookings/index"
  end

  # Cancels the signed-in user's own booking, then reconciles the event's capacity so the
  # earliest waitlisted booking is promoted into the freed seat (see
  # plan/build-plan.md "Capacity-Race Handling Approach").
  post "/bookings/:id/cancel" do
    require_login!

    with_access_token do |token|
      booking = Mudbase::BookingsRepo.find(access_token: token, id: params["id"])
      halt 404, erb(:"errors/not_found", layout: :layout) unless booking

      if booking[:userId] != @current_user[:id]
        flash_error("You can only cancel your own booking.")
        redirect back_or("/bookings")
      end

      unless %w[confirmed waitlisted].include?(booking[:status])
        flash_error("This booking can no longer be cancelled.")
        redirect back_or("/bookings")
      end

      event = Mudbase::EventsRepo.find(access_token: token, id: booking[:eventId])

      Mudbase::BookingsRepo.update!(access_token: token, id: booking[:_id], attributes: { status: "cancelled" })
      Mudbase::ActivityRepo.create!(
        access_token: token,
        attributes: {
          eventId: booking[:eventId], actorId: booking[:userId], actorName: booking[:userName],
          action: "booking_cancelled"
        },
      )
      Mudbase::Capacity.reconcile!(access_token: token, event_id: booking[:eventId], capacity: event[:capacity].to_i) if event
    end

    flash_notice("Booking cancelled.")
    redirect back_or("/bookings")
  end
end
