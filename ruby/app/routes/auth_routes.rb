# frozen_string_literal: true

# Login/logout. There is no registration UI in this app - both roles this project's Multi-Role
# feature is configured with (`organizer`/`attendee`) are provisioned out of band and already
# exist (see plan/build-plan.md "Auth Model"), and `login_local_user` is role-agnostic - the same
# endpoint authenticates either role.
class App < Sinatra::Base
  # Two pre-filled "Sign in as..." shortcuts for fast demoing without retyping credentials -
  # mirrors the reference Next.js app's `/login` quick-fill buttons, translated for a
  # server-rendered app with no client-side JS: each is its own tiny form posting straight to
  # `/login` with the role's demo credentials already in hidden fields.
  DEMO_ACCOUNTS = [
    { role: "organizer", label: "Organizer", email: "events.organizer.demo@gmail.com", password: "DemoTest123!" },
    { role: "attendee", label: "Attendee", email: "events.attendee.demo@gmail.com", password: "DemoTest123!" },
  ].freeze

  get "/login" do
    redirect "/" if logged_in?
    @email = ""
    @demo_accounts = DEMO_ACCOUNTS
    erb :"auth/login"
  end

  post "/login" do
    redirect "/" if logged_in?

    @email = params["email"].to_s.strip
    password = params["password"].to_s
    @demo_accounts = DEMO_ACCOUNTS

    if @email.empty? || password.empty?
      show_error_now("Enter your email and password.")
      halt erb(:"auth/login")
    end

    begin
      auth_session = Mudbase::AuthService.login!(email: @email, password: password)
      store_auth_session!(auth_session)
      flash_notice("Welcome back, #{auth_session.user[:firstName]} (#{auth_session.user[:customRole]}).")
      redirect consume_return_to
    rescue Mudbase::AuthError => e
      show_error_now(e.message)
      halt erb(:"auth/login")
    end
  end

  post "/logout" do
    Mudbase::AuthService.logout!(access_token) if access_token
    clear_auth_session!
    redirect "/login"
  end
end
