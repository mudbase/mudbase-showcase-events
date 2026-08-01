# frozen_string_literal: true

require "mudbase_sdk"
require_relative "client_factory"
require_relative "config"
require_relative "errors"

module Mudbase
  # Raised for any login/refresh failure the caller should show to the end user.
  class AuthError < StandardError
    def initialize(message, requires_verification: false)
      super(message)
      @requires_verification = requires_verification
    end

    def requires_verification?
      @requires_verification
    end
  end

  # Normalizes the raw parsed-JSON auth response (token/refreshToken/expiresIn/user) into a
  # small value object the session helpers can store. Field names stay camelCase-symbol,
  # matching the wire format exactly (see ClientFactory::OBJECT_RESPONSE for why this app reads
  # raw hashes here instead of the generated typed models).
  AuthSession = Struct.new(:token, :refresh_token, :expires_in, :user, keyword_init: true) do
    def self.from_hash(data)
      new(
        token: data[:token],
        refresh_token: data[:refreshToken],
        expires_in: data[:expiresIn] || 3600,
        user: data[:user] || {},
      )
    end
  end

  # Wraps `MudbaseSDK::AuthenticationApi#login_local_user`, `#refresh_token`, and
  # `#logout_local_user`. There is **no self-signup UI and no anonymous/guest session** in this
  # app - both accounts this project's Multi-Role feature is configured with
  # (`organizer`/`attendee`) are provisioned out of band (see plan/build-plan.md "Auth Model").
  # `login_local_user` itself is role-agnostic - the same endpoint authenticates either role and
  # returns whichever `customRole` the account was registered under.
  module AuthService
    def self.login!(email:, password:)
      request = MudbaseSDK::LoginLocalUserRequest.new(
        email: email,
        password: password,
        project_id: Mudbase::Config.project_id,
      )

      data, = Mudbase::ClientFactory.auth_api.login_local_user_with_http_info(
        request,
        Mudbase::ClientFactory::OBJECT_RESPONSE,
      )

      handle_auth_response(data)
    rescue MudbaseSDK::ApiError => e
      failure = Mudbase::ApiFailure.from(e)
      raise AuthError.new(failure.friendly_message, requires_verification: true) if failure.status == 403

      raise AuthError, failure.friendly_message
    end

    # Exchanges a stored (single-use, rotate-on-use) refresh token for a fresh access/refresh
    # pair. No `user` in the response (the identity/role doesn't change on refresh), so the
    # returned `AuthSession#user` is left `nil`; `SessionHelpers#refresh_access_token!` only
    # reads the refreshed token/expiry.
    def self.refresh!(refresh_token)
      request = MudbaseSDK::RefreshTokenRequest.new(refresh_token: refresh_token)
      data, = Mudbase::ClientFactory.auth_api.refresh_token_with_http_info(request)

      AuthSession.new(
        token: data.token,
        refresh_token: data.refresh_token,
        expires_in: data.expires_in || 3600,
        user: nil,
      )
    rescue MudbaseSDK::ApiError => e
      raise AuthError, Mudbase::ApiFailure.from(e).friendly_message
    end

    def self.logout!(access_token)
      Mudbase::ClientFactory.auth_api(access_token: access_token).logout_local_user
    rescue MudbaseSDK::ApiError
      # Best-effort: the local session cookie is cleared by the caller regardless, so a
      # failed server-side revoke (expired token, network blip) shouldn't block sign-out.
      nil
    end

    def self.handle_auth_response(data)
      if data[:token].nil? && data[:requireVerification]
        raise AuthError.new(
          "This account still needs email verification before it can sign in.",
          requires_verification: true,
        )
      end

      AuthSession.from_hash(data)
    end
    private_class_method :handle_auth_response
  end
end
