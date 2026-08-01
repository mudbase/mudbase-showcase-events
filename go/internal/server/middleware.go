package server

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"net/url"

	"github.com/mudbase/mudbase-showcase-events/go/internal/mbase"
	"github.com/mudbase/mudbase-showcase-events/go/internal/rbac"
	"github.com/mudbase/mudbase-showcase-events/go/internal/session"
)

// sessionMiddleware loads the visitor's session cookie and wires a TokenRefresher into the
// request context for every downstream mbase.List/Get/Create/Update/Delete call. There is no
// anonymous/guest session established here - every role, including attendee, must sign in with a
// real account (see plan/build-plan.md "Auth Flow"), so a visitor with no cookie simply proceeds
// signed-out and is redirected to /login by requireSignedIn on any route that needs an identity.
func (a *App) sessionMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		data, err := a.sessions.Load(r)
		if err != nil {
			log.Printf("server: session load failed: %v", err)
			http.Error(w, "Session error. Please clear your cookies and try again.", http.StatusInternalServerError)
			return
		}

		r = r.WithContext(mbase.WithTokenRefresher(r.Context(), a.tokenRefresher(w, r, data)))
		next.ServeHTTP(w, withSession(r, data))
	})
}

// tokenRefresher builds the mbase.TokenRefresher this request's context carries, so any
// List/Get/Create/Update/Delete call made deep in a handler can transparently recover from an
// expired access token: on a 401, mbase.callWithRefresh (see internal/mbase/refresh.go) invokes
// this closure, which exchanges the session's stored refresh token for a new pair via
// a.mudbase.Refresh, persists both back into the session cookie, and hands the new access token
// back for one retry.
func (a *App) tokenRefresher(w http.ResponseWriter, r *http.Request, data *session.Data) mbase.TokenRefresher {
	return func(ctx context.Context) (string, error) {
		refreshToken := data.RefreshToken()
		if refreshToken == "" {
			return "", fmt.Errorf("server: session has no refresh token to use")
		}

		result, err := a.mudbase.Refresh(ctx, refreshToken)
		if err != nil {
			return "", fmt.Errorf("server: refreshing access token: %w", err)
		}

		data.SetTokens(result.Token, result.RefreshToken)
		if err := data.Save(w, r); err != nil {
			return "", fmt.Errorf("server: persisting refreshed session token: %w", err)
		}
		return result.Token, nil
	}
}

// requireSignedIn gates a route on a real signed-in account, redirecting to sign in first and
// preserving the original path so login can send the visitor back.
func (a *App) requireSignedIn(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !sessionFrom(r).IsSignedIn() {
			redirectTo := "/login?redirect=" + url.QueryEscape(r.URL.Path)
			http.Redirect(w, r, redirectTo, http.StatusSeeOther)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// requireOrganizer gates a write route on the signed-in visitor's role, per the RBAC matrix in
// plan/build-plan.md. This is the "server-side enforcement" the task requires in addition to the
// templates hiding controls a role cannot use - it runs before the handler touches Mudbase at all.
// It is still only defense-in-depth: Mudbase's own collection permissions independently reject the
// exact same write with a 403 regardless of this middleware (see mbase.IsForbidden and the
// handlers' own error mapping) - verified live, see README "Live smoke test".
func (a *App) requireOrganizer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !rbac.CanManageEvents(sessionFrom(r).Role()) {
			redirectWithError(w, r, "/", "Only organizers can do that.")
			return
		}
		next.ServeHTTP(w, r)
	})
}
