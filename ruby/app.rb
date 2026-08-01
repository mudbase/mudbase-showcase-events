# frozen_string_literal: true

require "dotenv/load"
require "uri"
require "sinatra/base"

require_relative "lib/mudbase/config"
require_relative "lib/mudbase/client_factory"
require_relative "lib/mudbase/errors"
require_relative "lib/mudbase/auth_service"
require_relative "lib/mudbase/qr_token"
require_relative "lib/mudbase/events_repo"
require_relative "lib/mudbase/bookings_repo"
require_relative "lib/mudbase/activity_repo"
require_relative "lib/mudbase/capacity"
require_relative "lib/session_helpers"
require_relative "lib/view_helpers"

# Mudbase Showcase: Events - an event booking/ticketing platform built entirely on Mudbase (auth,
# database), rendered server-side with Sinatra + ERB. This is the Ruby reimplementation of the
# reference Next.js app (see ../web): same Mudbase project, same three collections
# (`events`/`bookings`/`activity`), same `organizer`/`attendee` RBAC matrix, same capacity-aware
# booking + waitlist-promotion algorithm - different stack, following the Sinatra structure the
# sibling `mudbase-showcase-kanban`/`mudbase-showcase-social`/`mudbase-showcase-ecommerce` ports
# established.
class App < Sinatra::Base
  configure do
    set :root, File.dirname(__FILE__)
    set :views, File.join(settings.root, "views")
    set :public_folder, File.join(settings.root, "public")
    set :show_exceptions, false
    set :raise_errors, false

    is_production = ENV.fetch("RACK_ENV", "development") == "production"
    set :session_secret, Mudbase::Config.session_secret
    set :sessions, {
      key: "mudbase_showcase_events.session",
      httponly: true,
      same_site: :lax,
      secure: is_production,
      expire_after: 60 * 60 * 12,
    }
  end

  configure :development do
    require "sinatra/reloader"
    register Sinatra::Reloader
  end

  helpers SessionHelpers
  helpers ViewHelpers

  before do
    @flash_notice = pop_flash_notice
    @flash_error = pop_flash_error
    @current_user = current_user
  end

  # `MudbaseSDK::ApiError` is what every generated API call raises on a non-2xx response
  # (invalid input, expired token, permission denial, etc.) - surfaced here as a flash-style
  # error banner instead of a raw 500, matching "never silently swallow errors" while still
  # giving the visitor something actionable. A 403 here means Mudbase's own collection
  # permissions rejected the write independently of this app's own `require_organizer!`/
  # `require_event_owner!` gates (see lib/session_helpers.rb) - the real enforcement boundary.
  error MudbaseSDK::ApiError do
    failure = Mudbase::ApiFailure.from(env["sinatra.error"])
    if failure.status == 401
      clear_auth_session!
      flash_error("Your session expired - please sign in again.")
      redirect "/login"
    else
      flash_error(failure.friendly_message)
      redirect back_or("/")
    end
  end

  error Mudbase::MissingEnvError do
    content_type :text
    status 500
    "Server misconfigured: #{env['sinatra.error'].message}"
  end

  not_found do
    erb :"errors/not_found", layout: :layout
  end

  error do
    logger.error(env["sinatra.error"]&.full_message) if env["sinatra.error"]
    erb :"errors/server_error", layout: :layout
  end

  helpers do
    def back_or(default_path)
      request.referrer && URI.parse(request.referrer).path != request.path ? request.referrer : default_path
    rescue URI::InvalidURIError
      default_path
    end
  end
end

require_relative "app/routes/auth_routes"
require_relative "app/routes/events_routes"
require_relative "app/routes/bookings_routes"
