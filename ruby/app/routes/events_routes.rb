# frozen_string_literal: true

# Event list/detail/CRUD + check-in. Create/edit/delete/check-in are organizer-only and scoped to
# the event's own organizer, per the RBAC matrix in plan/build-plan.md.
# `require_organizer!`/`require_event_owner!` (lib/session_helpers.rb) are this app's own
# server-side gates, checked before any Mudbase call is even attempted; Mudbase's own collection
# permissions (organizer: full CRUD, attendee: read-only on `events`) are the real enforcement
# boundary underneath them - verified live, see plan/build-plan.md "Live Smoke Test Results" for
# an attendee raw write attempt against `events` that the UI never exposes an affordance for.
class App < Sinatra::Base
  EVENTS_PAGE_SIZE = 10
  TITLE_MAX_LENGTH = 200
  DESCRIPTION_MAX_LENGTH = 2000
  LOCATION_MAX_LENGTH = 200
  CAPACITY_MIN = 1
  CAPACITY_MAX = 100_000

  get "/" do
    require_login!

    page = [params["page"].to_i, 1].max
    result = with_access_token { |token| Mudbase::EventsRepo.page(access_token: token, page: page, limit: EVENTS_PAGE_SIZE) }
    @events = result[:events]
    @pagination = result[:pagination]

    @confirmed_counts = with_access_token do |token|
      @events.to_h { |event| [event[:_id], Mudbase::BookingsRepo.confirmed_count(access_token: token, event_id: event[:_id])] }
    end

    erb :"events/index"
  end

  get "/events/new" do
    require_organizer!

    @event = { title: "", description: "", starts_at: "", location: "", capacity: "20" }
    @form_action = "/events"
    @form_title = "New event"
    erb :"events/form"
  end

  post "/events" do
    require_organizer!

    values = extract_event_form(params)
    errors = validate_event_form(values)
    if errors.any?
      @event = values
      @form_action = "/events"
      @form_title = "New event"
      show_error_now(errors.join(" "))
      halt erb(:"events/form")
    end

    event = with_access_token do |token|
      created = Mudbase::EventsRepo.create!(
        access_token: token,
        attributes: event_attributes(values).merge(
          organizerId: @current_user[:id],
          organizerName: "#{@current_user[:firstName]} #{@current_user[:lastName]}".strip,
        ),
      )
      Mudbase::ActivityRepo.create!(
        access_token: token,
        attributes: { eventId: created[:_id], action: "event_created", **actor_fields },
      )
      created
    end

    flash_notice("Event created.")
    redirect "/events/#{event[:_id]}"
  end

  get "/events/:id" do
    require_login!

    @event = with_access_token { |token| Mudbase::EventsRepo.find(access_token: token, id: params["id"]) }
    halt 404, erb(:"errors/not_found", layout: :layout) unless @event

    @confirmed = with_access_token { |token| Mudbase::BookingsRepo.confirmed_count(access_token: token, event_id: @event[:_id]) }
    @my_booking = with_access_token do |token|
      Mudbase::BookingsRepo.find_own(access_token: token, event_id: @event[:_id], user_id: @current_user[:id])
    end
    @is_owner = @event[:organizerId] == @current_user[:id]
    @activity = with_access_token { |token| Mudbase::ActivityRepo.for_event(access_token: token, event_id: @event[:_id]) }

    erb :"events/show"
  end

  get "/events/:id/edit" do
    event = with_access_token { |token| Mudbase::EventsRepo.find(access_token: token, id: params["id"]) }
    halt 404, erb(:"errors/not_found", layout: :layout) unless event
    require_event_owner!(event)

    @event = {
      title: event[:title].to_s,
      description: event[:description].to_s,
      starts_at: to_datetime_local_value(event[:startsAt]),
      location: event[:location].to_s,
      capacity: event[:capacity].to_s,
    }
    @form_action = "/events/#{event[:_id]}"
    @form_title = "Edit event"
    erb :"events/form"
  end

  post "/events/:id" do
    event = with_access_token { |token| Mudbase::EventsRepo.find(access_token: token, id: params["id"]) }
    halt 404, erb(:"errors/not_found", layout: :layout) unless event
    require_event_owner!(event)

    values = extract_event_form(params)
    errors = validate_event_form(values)
    if errors.any?
      @event = values
      @form_action = "/events/#{event[:_id]}"
      @form_title = "Edit event"
      show_error_now(errors.join(" "))
      halt erb(:"events/form")
    end

    with_access_token do |token|
      Mudbase::EventsRepo.update!(access_token: token, id: event[:_id], attributes: event_attributes(values))
      Mudbase::ActivityRepo.create!(
        access_token: token,
        attributes: { eventId: event[:_id], action: "event_updated", **actor_fields },
      )
    end

    flash_notice("Event updated.")
    redirect "/events/#{event[:_id]}"
  end

  post "/events/:id/delete" do
    event = with_access_token { |token| Mudbase::EventsRepo.find(access_token: token, id: params["id"]) }
    halt 404, erb(:"errors/not_found", layout: :layout) unless event
    require_event_owner!(event)

    with_access_token { |token| Mudbase::EventsRepo.delete!(access_token: token, id: event[:_id]) }

    flash_notice("Event deleted.")
    redirect "/"
  end

  get "/events/:id/checkin" do
    event = with_access_token { |token| Mudbase::EventsRepo.find(access_token: token, id: params["id"]) }
    halt 404, erb(:"errors/not_found", layout: :layout) unless event
    require_event_owner!(event)

    @event = event
    @result = nil
    @qr_token_value = ""
    erb :"events/checkin"
  end

  # Look up a booking within this event by its scanned/pasted `qrToken` and, if eligible, check
  # it in - mirrors the reference web app's `useCheckIn` outcome branching exactly (see
  # plan/build-plan.md "Check-In Flow").
  post "/events/:id/checkin" do
    event = with_access_token { |token| Mudbase::EventsRepo.find(access_token: token, id: params["id"]) }
    halt 404, erb(:"errors/not_found", layout: :layout) unless event
    require_event_owner!(event)

    @event = event
    @qr_token_value = params["qr_token"].to_s.strip

    if @qr_token_value.empty?
      @result = { outcome: :not_found }
      halt erb(:"events/checkin")
    end

    booking = with_access_token do |token|
      Mudbase::BookingsRepo.find_by_qr_token(access_token: token, event_id: event[:_id], qr_token: @qr_token_value)
    end

    @result =
      case booking && booking[:status]
      when nil
        { outcome: :not_found }
      when "checked_in"
        { outcome: :already_checked_in, booking: booking }
      when "cancelled"
        { outcome: :cancelled, booking: booking }
      when "waitlisted"
        { outcome: :waitlisted, booking: booking }
      else
        updated = with_access_token do |token|
          checked_in = Mudbase::BookingsRepo.update!(access_token: token, id: booking[:_id], attributes: { status: "checked_in" })
          Mudbase::ActivityRepo.create!(
            access_token: token,
            attributes: {
              eventId: event[:_id], actorId: booking[:userId], actorName: booking[:userName], action: "checked_in"
            },
          )
          checked_in
        end
        { outcome: :checked_in, booking: updated }
      end

    erb :"events/checkin"
  end

  # Capacity-aware booking: `POST /events/:id/book` - see plan/build-plan.md "Capacity-Race
  # Handling Approach". Any signed-in user may book an event that isn't their own (the show view
  # hides the Book form on an organizer's own event, matching the reference web app's UX gating -
  # this isn't a role restriction, so it isn't re-enforced as a hard 403 here, mirroring the
  # reference implementation's own documented scope decision).
  post "/events/:id/book" do
    require_login!

    event = with_access_token { |token| Mudbase::EventsRepo.find(access_token: token, id: params["id"]) }
    halt 404, erb(:"errors/not_found", layout: :layout) unless event

    with_access_token do |token|
      confirmed = Mudbase::BookingsRepo.confirmed_count(access_token: token, event_id: event[:_id])
      initial_status = confirmed < event[:capacity].to_i ? "confirmed" : "waitlisted"
      qr_token = Mudbase::QrToken.generate

      Mudbase::BookingsRepo.create!(
        access_token: token,
        attributes: {
          eventId: event[:_id], userId: @current_user[:id],
          userName: "#{@current_user[:firstName]} #{@current_user[:lastName]}".strip,
          status: initial_status, qrToken: qr_token,
        },
      )
      Mudbase::ActivityRepo.create!(
        access_token: token,
        attributes: {
          eventId: event[:_id],
          action: initial_status == "confirmed" ? "booking_confirmed" : "booking_waitlisted",
          **actor_fields
        },
      )
      Mudbase::Capacity.reconcile!(access_token: token, event_id: event[:_id], capacity: event[:capacity].to_i)
    end

    flash_notice("Booking requested.")
    redirect "/events/#{event[:_id]}"
  end

  helpers do
    # `{actorId:, actorName:}` for the signed-in user, written onto every activity row this app
    # creates directly (as opposed to rows describing another user's booking, which carry that
    # user's own id/name instead - see `app/routes/bookings_routes.rb`).
    def actor_fields
      { actorId: @current_user[:id], actorName: "#{@current_user[:firstName]} #{@current_user[:lastName]}".strip }
    end

    def extract_event_form(params)
      {
        title: params["title"].to_s.strip,
        description: params["description"].to_s.strip,
        starts_at: params["starts_at"].to_s.strip,
        location: params["location"].to_s.strip,
        capacity: params["capacity"].to_s.strip,
      }
    end

    def validate_event_form(values)
      errors = []
      errors << "Title is required." if values[:title].empty?
      errors << "Keep the title under #{TITLE_MAX_LENGTH} characters." if values[:title].length > TITLE_MAX_LENGTH
      if values[:description].length > DESCRIPTION_MAX_LENGTH
        errors << "Keep the description under #{DESCRIPTION_MAX_LENGTH} characters."
      end
      errors << "Date and time is required." if values[:starts_at].empty?
      if !values[:starts_at].empty? && parse_starts_at(values[:starts_at]).nil?
        errors << "Enter a valid date and time."
      end
      errors << "Location is required." if values[:location].empty?
      errors << "Keep the location under #{LOCATION_MAX_LENGTH} characters." if values[:location].length > LOCATION_MAX_LENGTH

      capacity_int = Integer(values[:capacity], exception: false)
      if capacity_int.nil?
        errors << "Capacity must be a whole number."
      elsif capacity_int < CAPACITY_MIN
        errors << "Capacity must be at least #{CAPACITY_MIN}."
      elsif capacity_int > CAPACITY_MAX
        errors << "Capacity is unrealistically large."
      end
      errors
    end

    def parse_starts_at(value)
      Time.parse(value)
    rescue ArgumentError, TypeError
      nil
    end

    def event_attributes(values)
      {
        title: values[:title],
        description: values[:description],
        startsAt: parse_starts_at(values[:starts_at]).iso8601,
        location: values[:location],
        capacity: Integer(values[:capacity]),
      }
    end
  end
end
