# frozen_string_literal: true

require "time"
require "rqrcode"

# ERB helpers shared by every view.
module ViewHelpers
  # Mirrors the reference web app's `ACTIVITY_LABELS` (`src/types/activity.ts`) - the
  # human-readable suffix appended after the actor's name in the activity feed.
  ACTIVITY_LABELS = {
    "booking_confirmed" => "booked (confirmed)",
    "booking_waitlisted" => "joined the waitlist",
    "booking_cancelled" => "cancelled their booking",
    "booking_promoted" => "was promoted from the waitlist",
    "checked_in" => "checked in",
    "event_created" => "created this event",
    "event_updated" => "updated this event",
  }.freeze

  def h(text)
    Rack::Utils.escape_html(text.to_s)
  end

  def format_datetime(iso_string)
    return "" if iso_string.nil? || iso_string.empty?

    Time.parse(iso_string).strftime("%b %-d, %Y %-I:%M %p")
  rescue ArgumentError
    iso_string.to_s
  end

  # For pre-filling `<input type="datetime-local">` on the edit-event form - local time, no
  # timezone/seconds, mirroring the reference web app's `toDateTimeLocalValue`.
  def to_datetime_local_value(iso_string)
    return "" if iso_string.nil? || iso_string.empty?

    Time.parse(iso_string).strftime("%Y-%m-%dT%H:%M")
  rescue ArgumentError
    ""
  end

  # Compact "3m", "2h", "5d" style relative time for the activity feed - falls back to an
  # absolute date once it's more than a week old, same threshold the reference web app's
  # `formatRelativeTime` uses.
  def format_relative(iso_string)
    return "" if iso_string.nil? || iso_string.empty?

    then_time = Time.parse(iso_string)
    seconds = (Time.now - then_time).to_i
    return "just now" if seconds < 60
    return "#{seconds / 60}m" if seconds < 3600
    return "#{seconds / 3600}h" if seconds < 86_400
    return "#{seconds / 86_400}d" if seconds < 604_800

    then_time.strftime("%b %-d, %Y")
  rescue ArgumentError
    iso_string.to_s
  end

  # Human-readable label for an `activity` row's `action` field, mirroring the reference web
  # app's `ACTIVITY_LABELS` (`src/types/activity.ts`).
  def activity_text(entry)
    label = ACTIVITY_LABELS[entry[:action]] || "updated the event"
    "#{h(entry[:actorName])} #{label}"
  end

  # `[css_class, label]` for the capacity indicator, mirroring the reference web app's
  # `CapacityBadge` thresholds: full once `confirmed >= capacity`, a "closing soon" warning once
  # remaining seats drop to <=10% of capacity (minimum 1), otherwise a plain "booked" count.
  def capacity_badge(confirmed, capacity)
    remaining = capacity - confirmed
    if remaining <= 0
      ["badge-full", "Full · #{confirmed}/#{capacity}"]
    elsif remaining <= [1, (capacity * 0.1).ceil].max
      ["badge-warning", "#{confirmed}/#{capacity} booked"]
    else
      ["badge-success", "#{confirmed}/#{capacity} booked"]
    end
  end

  BOOKING_STATUS_LABELS = {
    "confirmed" => "Confirmed",
    "waitlisted" => "Waitlisted",
    "cancelled" => "Cancelled",
    "checked_in" => "Checked in",
  }.freeze

  def booking_status_label(status)
    BOOKING_STATUS_LABELS[status] || status.to_s.capitalize
  end

  def booking_status_class(status)
    case status
    when "confirmed" then "status-confirmed"
    when "waitlisted" then "status-waitlisted"
    when "checked_in" then "status-checked-in"
    else "status-cancelled"
    end
  end

  # Server-rendered inline SVG for a booking's `qrToken` - the check-in flow's scannable
  # artifact, mirroring the reference web app's client-rendered `<QRCodeSVG>` (`qrcode.react`)
  # but generated here on the server since this app ships zero client-side JavaScript. Returned
  # markup is trusted (server-generated from a hex token, never raw user input) so views
  # interpolate it directly without `h()`. `standalone: true` is required to get the wrapping
  # `<svg>...</svg>` tag rather than a bare `<path>`, but rqrcode always prepends an
  # `<?xml version="1.0" standalone="yes"?>` declaration in that mode - invalid as inline HTML
  # content (an XML prolog belongs at the top of a whole document, not embedded mid-page), so
  # it's stripped here before the markup is embedded in a view.
  def qr_svg(data)
    svg = RQRCode::QRCode.new(data).as_svg(
      offset: 0,
      color: "000",
      fill: "fff",
      shape_rendering: "crispEdges",
      module_size: 4,
      standalone: true,
      use_path: true,
    )
    svg.sub(/\A<\?xml[^>]*\?>/, "")
  end
end
