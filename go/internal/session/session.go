// Package session wraps gorilla/sessions to hold the visitor's per-request state - the
// Mudbase-issued JWT and a cached snapshot of the signed-in user - in a signed, encrypted, httpOnly
// cookie. The JWT never reaches client-side JavaScript because there is none: every page is
// server-rendered, so the cookie is the only place a token can live.
package session

import (
	"crypto/sha256"
	"fmt"
	"net/http"

	"github.com/gorilla/sessions"

	"github.com/mudbase/mudbase-showcase-events/go/internal/mbase"
)

const cookieName = "mudbase_showcase_events_session"

const (
	keyAccessToken  = "access_token"
	keyRefreshToken = "refresh_token"
	keyUserID       = "user_id"
	keyEmail        = "email"
	keyFirstName    = "first_name"
	keyLastName     = "last_name"
	keyRole         = "role"
)

const thirtyDaysSeconds = 60 * 60 * 24 * 30

// Store is the app-wide cookie session store.
type Store struct {
	cookies *sessions.CookieStore
}

// New builds a Store whose signing/encryption keys are derived deterministically from secret, so
// sessions created before a restart remain valid afterward (a random key per process would log
// out every visitor on every deploy). secret must be at least 32 bytes - enforced in
// internal/config.
func New(secret string, secureCookie bool) *Store {
	hashKey := sha256.Sum256([]byte(secret + ":hash"))
	blockKey := sha256.Sum256([]byte(secret + ":block"))

	cookies := sessions.NewCookieStore(hashKey[:], blockKey[:])
	cookies.Options = &sessions.Options{
		Path:     "/",
		MaxAge:   thirtyDaysSeconds,
		HttpOnly: true,
		Secure:   secureCookie,
		SameSite: http.SameSiteLaxMode,
	}
	return &Store{cookies: cookies}
}

// Data is the decoded session for one request, mutated in place and persisted via Save.
type Data struct {
	sess *sessions.Session
}

// Load reads (or, on first visit / a corrupted cookie, initializes) the session for r.
func (s *Store) Load(r *http.Request) (*Data, error) {
	sess, err := s.cookies.Get(r, cookieName)
	if err != nil {
		// gorilla/sessions returns both an error AND a new empty session when the cookie is
		// missing, expired, or fails to decode (e.g. after a SESSION_SECRET rotation) - treating
		// that as "start a fresh, signed-out session" is correct here; only a nil session is
		// unrecoverable.
		if sess == nil {
			return nil, fmt.Errorf("session: loading cookie: %w", err)
		}
	}
	return &Data{sess: sess}, nil
}

// Save persists any changes made to d back onto the response as a Set-Cookie header.
func (d *Data) Save(w http.ResponseWriter, r *http.Request) error {
	if err := d.sess.Save(r, w); err != nil {
		return fmt.Errorf("session: saving cookie: %w", err)
	}
	return nil
}

func (d *Data) str(key string) string {
	v, _ := d.sess.Values[key].(string)
	return v
}

// AccessToken returns the current Mudbase bearer token, or "" before any session is established.
func (d *Data) AccessToken() string { return d.str(keyAccessToken) }

// RefreshToken returns the current Mudbase refresh token, or "" before any session is established
// (or after a refresh whose response - unexpectedly - omitted one).
func (d *Data) RefreshToken() string { return d.str(keyRefreshToken) }

// UserID returns the signed-in user's Mudbase ID, or "" if nobody is signed in.
func (d *Data) UserID() string { return d.str(keyUserID) }

// Email returns the current user's email address.
func (d *Data) Email() string { return d.str(keyEmail) }

// FirstName returns the current user's first name.
func (d *Data) FirstName() string { return d.str(keyFirstName) }

// LastName returns the current user's last name.
func (d *Data) LastName() string { return d.str(keyLastName) }

// DisplayName returns "First Last" for the signed-in user, matching how organizerName/userName/
// actorName are written on create (see server/handlers_events.go, handlers_bookings.go).
func (d *Data) DisplayName() string {
	first, last := d.FirstName(), d.LastName()
	if first == "" && last == "" {
		return "Someone"
	}
	if last == "" {
		return first
	}
	if first == "" {
		return last
	}
	return first + " " + last
}

// Role returns the Mudbase Multi-Role customRole ("organizer"/"attendee"), or "" before any
// session is established.
func (d *Data) Role() string { return d.str(keyRole) }

// IsSignedIn reports whether this request has a real signed-in account. There is no anonymous/
// guest session in this app - every role, including attendee, must authenticate (see
// plan/build-plan.md "Auth Flow").
func (d *Data) IsSignedIn() bool { return d.UserID() != "" }

// SetUser stores the given auth result as the session's current identity.
func (d *Data) SetUser(auth mbase.AuthResult) {
	d.sess.Values[keyAccessToken] = auth.Token
	d.sess.Values[keyRefreshToken] = auth.RefreshToken
	d.sess.Values[keyUserID] = auth.User.ID
	d.sess.Values[keyEmail] = auth.User.Email
	d.sess.Values[keyFirstName] = auth.User.FirstName
	d.sess.Values[keyLastName] = auth.User.LastName
	d.sess.Values[keyRole] = auth.User.CustomRole
}

// SetTokens replaces just the access/refresh token pair, leaving every other identity field (user
// ID, name, role, ...) untouched - used after a transparent token refresh (internal/mbase.Refresh),
// whose response carries no `user` object to re-derive those fields from.
func (d *Data) SetTokens(accessToken, refreshToken string) {
	d.sess.Values[keyAccessToken] = accessToken
	d.sess.Values[keyRefreshToken] = refreshToken
}

// ClearUser wipes every session field (used on logout).
func (d *Data) ClearUser() {
	delete(d.sess.Values, keyAccessToken)
	delete(d.sess.Values, keyRefreshToken)
	delete(d.sess.Values, keyUserID)
	delete(d.sess.Values, keyEmail)
	delete(d.sess.Values, keyFirstName)
	delete(d.sess.Values, keyLastName)
	delete(d.sess.Values, keyRole)
}
