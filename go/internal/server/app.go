// Package server wires the app's HTTP surface: routing, session handling, and every
// server-rendered page handler, on top of internal/store's domain services.
package server

import (
	"fmt"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/mudbase/mudbase-showcase-events/go/internal/config"
	"github.com/mudbase/mudbase-showcase-events/go/internal/mbase"
	"github.com/mudbase/mudbase-showcase-events/go/internal/session"
	"github.com/mudbase/mudbase-showcase-events/go/internal/store"
)

// App bundles every dependency the HTTP handlers need.
type App struct {
	cfg       *config.Config
	sessions  *session.Store
	mudbase   *mbase.Client
	events    *store.EventService
	bookings  *store.BookingService
	activity  *store.ActivityService
	templates *Templates
}

// New builds the App and its full dependency graph from cfg.
func New(cfg *config.Config) (*App, error) {
	templates, err := loadTemplates()
	if err != nil {
		return nil, fmt.Errorf("server: loading templates: %w", err)
	}

	client := mbase.New(cfg)
	activity := store.NewActivityService(client, cfg.ActivityCollectionID)
	events := store.NewEventService(client, cfg.EventsCollectionID, activity)
	bookings := store.NewBookingService(client, cfg.BookingsCollectionID, activity)

	return &App{
		cfg:       cfg,
		sessions:  session.New(cfg.SessionSecret, cfg.CookieSecure),
		mudbase:   client,
		events:    events,
		bookings:  bookings,
		activity:  activity,
		templates: templates,
	}, nil
}

// Routes builds the full chi router for this app. Static assets are mounted outside the session
// middleware group - a stylesheet request has no business loading a session cookie.
func (a *App) Routes() http.Handler {
	root := chi.NewRouter()
	root.Use(middleware.Logger)
	root.Use(middleware.Recoverer)

	staticHandler := http.FileServer(http.FS(staticFS))
	root.Get("/static/*", staticHandler.ServeHTTP)

	r := chi.NewRouter()
	r.Use(a.sessionMiddleware)

	r.Get("/login", a.handleLoginShow)
	r.Post("/login", a.handleLoginSubmit)
	r.Post("/logout", a.handleLogout)
	r.Get("/register", a.handleRegisterShow)
	r.Post("/register", a.handleRegisterSubmit)

	r.With(a.requireSignedIn).Get("/", a.handleEventList)
	r.With(a.requireSignedIn, a.requireOrganizer).Get("/events/new", a.handleEventNewShow)
	r.With(a.requireSignedIn, a.requireOrganizer).Post("/events/new", a.handleEventNewSubmit)
	r.With(a.requireSignedIn).Get("/events/{id}", a.handleEventDetail)
	r.With(a.requireSignedIn, a.requireOrganizer).Get("/events/{id}/edit", a.handleEventEditShow)
	r.With(a.requireSignedIn, a.requireOrganizer).Post("/events/{id}/edit", a.handleEventEditSubmit)
	r.With(a.requireSignedIn, a.requireOrganizer).Post("/events/{id}/delete", a.handleEventDelete)
	r.With(a.requireSignedIn, a.requireOrganizer).Get("/events/{id}/checkin", a.handleCheckInShow)
	r.With(a.requireSignedIn, a.requireOrganizer).Post("/events/{id}/checkin", a.handleCheckInSubmit)
	r.With(a.requireSignedIn).Post("/events/{id}/book", a.handleBookingCreate)

	r.With(a.requireSignedIn).Get("/bookings", a.handleMyBookings)
	r.With(a.requireSignedIn).Post("/bookings/{id}/cancel", a.handleBookingCancel)

	root.Mount("/", r)
	return root
}
