package server

import (
	"log"
	"net/http"
	"net/mail"
	"net/url"
	"strings"

	"github.com/mudbase/mudbase-showcase-events/go/internal/mbase"
	"github.com/mudbase/mudbase-showcase-events/go/internal/rbac"
)

// LoginData is the /login page's content payload.
type LoginData struct {
	Base
	Redirect string
}

func (a *App) handleLoginShow(w http.ResponseWriter, r *http.Request) {
	data := sessionFrom(r)
	if data.IsSignedIn() {
		http.Redirect(w, r, "/", http.StatusSeeOther)
		return
	}
	view := LoginData{
		Base:     a.baseView(r, "Sign in"),
		Redirect: r.URL.Query().Get("redirect"),
	}
	view.FlashError, view.FlashSuccess = flashFromQuery(r)
	a.render(w, r, http.StatusOK, "login.html", view)
}

// loginError redirects back to /login preserving both the flash message and any pending
// post-login redirect target.
func loginError(w http.ResponseWriter, r *http.Request, redirect, message string) {
	q := url.Values{"error": {message}}
	if redirect != "" {
		q.Set("redirect", redirect)
	}
	http.Redirect(w, r, "/login?"+q.Encode(), http.StatusSeeOther)
}

func (a *App) handleLoginSubmit(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		a.serverError(w, r, err)
		return
	}
	email := r.FormValue("email")
	password := r.FormValue("password")
	redirect := r.FormValue("redirect")

	if _, err := mail.ParseAddress(email); err != nil {
		loginError(w, r, redirect, "Enter a valid email address.")
		return
	}
	if password == "" {
		loginError(w, r, redirect, "Password is required.")
		return
	}

	auth, err := a.mudbase.Login(r.Context(), email, password)
	if err != nil {
		loginError(w, r, redirect, mbase.FriendlyMessage(err))
		return
	}

	data := sessionFrom(r)
	data.SetUser(auth)
	if err := data.Save(w, r); err != nil {
		a.serverError(w, r, err)
		return
	}

	target := "/"
	if redirect != "" {
		target = redirect
	}
	http.Redirect(w, r, target, http.StatusSeeOther)
}

// handleLogout revokes the session's token server-side (best-effort - a failure here shouldn't
// block the visitor from being signed out locally) and clears the local session identity.
func (a *App) handleLogout(w http.ResponseWriter, r *http.Request) {
	data := sessionFrom(r)
	if token := data.AccessToken(); token != "" {
		if err := a.mudbase.Logout(r.Context(), token); err != nil {
			log.Printf("server: logout: %v", mbase.FriendlyMessage(err))
		}
	}
	data.ClearUser()
	if err := data.Save(w, r); err != nil {
		a.serverError(w, r, err)
		return
	}
	http.Redirect(w, r, "/login", http.StatusSeeOther)
}

// RegisterData is the /register page's content payload.
type RegisterData struct {
	Base
}

func (a *App) handleRegisterShow(w http.ResponseWriter, r *http.Request) {
	data := sessionFrom(r)
	if data.IsSignedIn() {
		http.Redirect(w, r, "/", http.StatusSeeOther)
		return
	}
	view := RegisterData{Base: a.baseView(r, "Create account")}
	view.FlashError, view.FlashSuccess = flashFromQuery(r)
	a.render(w, r, http.StatusOK, "register.html", view)
}

// handleRegisterSubmit signs up a brand-new account under the chosen role
// ("organizer"/"attendee") via the public RegisterWithRole endpoint - a nice-to-have alongside the
// two shared demo accounts (see plan/build-plan.md "Auth Flow"). When the project requires email
// verification, the visitor is sent to /login with an explanatory message rather than a session
// being silently (and incorrectly) established without a token.
func (a *App) handleRegisterSubmit(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		a.serverError(w, r, err)
		return
	}
	role := r.FormValue("role")
	email := r.FormValue("email")
	password := r.FormValue("password")
	firstName := strings.TrimSpace(r.FormValue("firstName"))
	lastName := strings.TrimSpace(r.FormValue("lastName"))

	if !rbac.IsValid(role) {
		redirectWithError(w, r, "/register", "Choose whether you're signing up as an organizer or an attendee.")
		return
	}
	if _, err := mail.ParseAddress(email); err != nil {
		redirectWithError(w, r, "/register", "Enter a valid email address.")
		return
	}
	if len(password) < 8 {
		redirectWithError(w, r, "/register", "Password must be at least 8 characters.")
		return
	}
	if firstName == "" || lastName == "" {
		redirectWithError(w, r, "/register", "First and last name are required.")
		return
	}

	auth, err := a.mudbase.Register(r.Context(), role, email, password, firstName, lastName)
	if err != nil {
		redirectWithError(w, r, "/register", mbase.FriendlyMessage(err))
		return
	}

	if auth.RequireVerification {
		redirectWithSuccess(w, r, "/login", "Account created. Check your email to verify it, then sign in.")
		return
	}

	data := sessionFrom(r)
	data.SetUser(auth)
	if err := data.Save(w, r); err != nil {
		a.serverError(w, r, err)
		return
	}
	http.Redirect(w, r, "/", http.StatusSeeOther)
}
