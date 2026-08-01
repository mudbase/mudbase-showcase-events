package server

import (
	"log"
	"net/http"
	"net/url"

	"github.com/mudbase/mudbase-showcase-events/go/internal/mbase"
)

// flashFromQuery reads the PRG-pattern (POST/Redirect/GET) flash query params this app uses
// instead of a stateful flash-message cookie: every state-changing POST handler redirects to a
// GET with ?error= or ?success= describing the outcome.
func flashFromQuery(r *http.Request) (errMsg, successMsg string) {
	return r.URL.Query().Get("error"), r.URL.Query().Get("success")
}

// redirectWithError redirects to path with an ?error= flash message.
func redirectWithError(w http.ResponseWriter, r *http.Request, path, message string) {
	http.Redirect(w, r, path+"?error="+url.QueryEscape(message), http.StatusSeeOther)
}

// redirectWithSuccess redirects to path with a ?success= flash message.
func redirectWithSuccess(w http.ResponseWriter, r *http.Request, path, message string) {
	http.Redirect(w, r, path+"?success="+url.QueryEscape(message), http.StatusSeeOther)
}

// serverError logs the real error server-side and shows the visitor a generic message - never the
// raw error text, which could leak internal details (collection IDs, stack-shaped SDK errors).
func (a *App) serverError(w http.ResponseWriter, r *http.Request, err error) {
	log.Printf("server: %s %s: %v", r.Method, r.URL.Path, err)
	http.Error(w, "Something went wrong on our end. Please try again.", http.StatusInternalServerError)
}

// render is a thin wrapper over Templates.Render that logs (rather than double-writes to) any
// error executing the template, since headers/status have already been sent by that point.
func (a *App) render(w http.ResponseWriter, r *http.Request, status int, name string, data interface{}) {
	if err := a.templates.Render(w, status, name, data); err != nil {
		log.Printf("server: %s %s: %v", r.Method, r.URL.Path, err)
	}
}

// mutationError redirects to path with a message appropriate to err: Mudbase's own collection
// permissions rejecting the write (mbase.IsForbidden - the real RBAC enforcement, independent of
// this app's own requireOrganizer middleware) get a specific, honest message; everything else gets
// a generic one so no internal detail (collection IDs, SDK error shapes) leaks to the page.
func mutationError(w http.ResponseWriter, r *http.Request, path string, err error, genericMessage string) {
	if mbase.IsForbidden(err) {
		redirectWithError(w, r, path, "The server rejected this action: your role doesn't have permission to do that.")
		return
	}
	redirectWithError(w, r, path, genericMessage)
}
