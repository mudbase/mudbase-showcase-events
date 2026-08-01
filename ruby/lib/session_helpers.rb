# frozen_string_literal: true

require_relative "mudbase/errors"
require_relative "mudbase/auth_service"

# Sinatra helpers for reading/writing the signed-in user's state. There is **no anonymous/guest
# session** in this app - every page except `/login` requires a real signed-in account, for both
# roles (`organizer`/`attendee`), since this project has no public role configured (see
# plan/build-plan.md "Auth Flow"). The Mudbase-issued JWT is held only inside the Rack session
# cookie (encrypted + signed + httponly via `Rack::Session::Cookie`, configured in app.rb) -
# never rendered into a page or exposed to client-side JavaScript.
#
# Refresh-token rotation: every route that calls Mudbase routes its access token through
# `with_access_token`, which proactively refreshes a token that's within
# `TOKEN_REFRESH_MARGIN_SECONDS` of its tracked expiry, and - the same as the reference Next.js
# app's `MudbaseClient#request` - reactively refreshes and retries exactly once on a real 401
# from the server. Only when the refresh token itself is rejected (expired/already
# rotated-away/revoked) does the session actually get torn down, via `MudbaseSDK::ApiError`
# bubbling up to app.rb's global 401 handler, which calls `clear_auth_session!` and redirects to
# `/login`.
module SessionHelpers
  TOKEN_REFRESH_MARGIN_SECONDS = 60

  def store_auth_session!(auth_session)
    session[:token] = auth_session.token
    session[:refresh_token] = auth_session.refresh_token
    session[:expires_at] = Time.now.to_i + auth_session.expires_in.to_i
    session[:user] = auth_session.user
  end

  def clear_auth_session!
    session.clear
  end

  def access_token
    session[:token]
  end

  def current_user
    session[:user]
  end

  def logged_in?
    !current_user.nil?
  end

  # Wraps every Mudbase call this app makes (every read and every write goes through a signed-in
  # user's own token - there is no separate guest path). If no refresh token is stored, or the
  # refresh token itself is rejected, the original `MudbaseSDK::ApiError` propagates to app.rb's
  # global handler, which logs the session out.
  def with_access_token
    refresh_access_token! if token_expiring_soon?
    yield session[:token]
  rescue MudbaseSDK::ApiError => e
    failure = Mudbase::ApiFailure.from(e)
    raise e unless failure.status == 401
    raise e unless refresh_access_token!

    yield session[:token]
  end

  def token_expiring_soon?
    session[:expires_at].nil? || Time.now.to_i >= session[:expires_at] - TOKEN_REFRESH_MARGIN_SECONDS
  end

  # @return [Boolean] whether the refresh succeeded and `session[:token]` is now fresh.
  def refresh_access_token!
    return false unless session[:refresh_token]

    auth_session = Mudbase::AuthService.refresh!(session[:refresh_token])
    session[:token] = auth_session.token
    session[:refresh_token] = auth_session.refresh_token
    session[:expires_at] = Time.now.to_i + auth_session.expires_in.to_i
    true
  rescue Mudbase::AuthError
    false
  end

  # ── Role helpers (RBAC matrix, plan/build-plan.md) ──────────────────────────────────────
  # Mudbase's own collection permissions are the real enforcement boundary (this project's
  # `events`/`bookings`/`activity` collections are configured with organizer having full CRUD and
  # attendee limited to reads + managing their own bookings/activity - see "Live smoke test
  # results" below for a raw-fetch write attempt bypassing this app's routes entirely). These
  # helpers are this app's own *additional* server-side gate: every organizer-only mutating route
  # calls `require_organizer!`/`require_event_owner!` before ever calling Mudbase, rather than
  # only hiding buttons in the view - "don't rely on UI-only gating".

  def current_role
    current_user && current_user[:customRole]
  end

  def organizer?
    current_role == "organizer"
  end

  def attendee?
    current_role == "attendee"
  end

  def require_login!
    return if logged_in?

    session[:return_to] = request.path_info
    redirect "/login"
  end

  # Server-side gate for event create/edit/delete and the check-in page - organizer role only.
  # This is checked *before* this app ever calls Mudbase (see "RBAC enforcement" in README.md).
  def require_organizer!
    require_login!
    return if organizer?

    flash_error("Only organizers can do that.")
    redirect back_or("/")
  end

  # Narrower gate for edit/delete/check-in: organizer role AND the event's own organizer -
  # matches the reference web app's `organizerId === session.user.id` ownership check, enforced
  # here server-side rather than only as a hidden affordance.
  def require_event_owner!(event)
    require_organizer!
    return if event && event[:organizerId] == current_user[:id]

    flash_error("You can only manage events you organize.")
    redirect back_or("/")
  end

  def consume_return_to
    session.delete(:return_to) || "/"
  end

  # For "set then redirect" flows: written to the session so the *next* request's `before`
  # filter (which runs before the route body, and so before any `flash_error`/`flash_notice`
  # call made this request) can pick it up via pop_flash_notice/pop_flash_error.
  def flash_notice(message)
    session[:flash_notice] = message
  end

  def flash_error(message)
    session[:flash_error] = message
  end

  def pop_flash_notice
    session.delete(:flash_notice)
  end

  def pop_flash_error
    session.delete(:flash_error)
  end

  # For "validate, then re-render the same page in this same response" flows (a failed
  # login/form submission). `@flash_error`/`@flash_notice` are already populated for this
  # request by the `before` filter *before* the route body runs, so a form-validation failure
  # has to set the ivar directly - writing to session here would only become visible on the
  # *following* request, leaving this response's re-rendered form with no visible error.
  def show_error_now(message)
    @flash_error = message
  end

  def show_notice_now(message)
    @flash_notice = message
  end
end
