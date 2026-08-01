package server

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/mudbase/mudbase-showcase-events/go/internal/mbase"
)

// handleBookingCreate books eventID for the signed-in visitor, using the capacity-race approach
// documented in ../../web/plan/build-plan.md. The UI hides the Book button on an organizer's own
// event and once an active (confirmed/waitlisted) booking already exists, but - matching the
// reference web app - creating a booking is not otherwise restricted by role.
func (a *App) handleBookingCreate(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	data := sessionFrom(r)
	token := data.AccessToken()

	event, err := a.events.ByID(r.Context(), token, id)
	if err != nil {
		redirectWithError(w, r, "/", "That event couldn't be found.")
		return
	}

	if _, err := a.bookings.Create(r.Context(), token, event.ID, event.Capacity, data.UserID(), data.DisplayName()); err != nil {
		mutationError(w, r, "/events/"+id, err, "Couldn't create that booking. Please try again.")
		return
	}

	redirectWithSuccess(w, r, "/events/"+id, "Booking created - check /bookings for your ticket.")
}

// handleBookingCancel cancels one of the signed-in visitor's own bookings, then reconciles so the
// earliest waitlisted booking on that event is promoted into the freed seat.
func (a *App) handleBookingCancel(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	data := sessionFrom(r)
	token := data.AccessToken()

	booking, err := a.bookings.ByID(r.Context(), token, id)
	if err != nil {
		redirectWithError(w, r, "/bookings", "That booking couldn't be found.")
		return
	}
	if booking.UserID != data.UserID() {
		redirectWithError(w, r, "/bookings", "You can only cancel your own bookings.")
		return
	}

	event, err := a.events.ByID(r.Context(), token, booking.EventID)
	if err != nil {
		redirectWithError(w, r, "/bookings", "That event couldn't be found.")
		return
	}

	if err := a.bookings.Cancel(r.Context(), token, booking.ID, booking.EventID, event.Capacity, data.UserID(), data.DisplayName()); err != nil {
		if mbase.IsForbidden(err) {
			redirectWithError(w, r, "/bookings", "The server rejected this action: your role doesn't have permission to do that.")
			return
		}
		redirectWithError(w, r, "/bookings", "Couldn't cancel that booking. Please try again.")
		return
	}

	redirectWithSuccess(w, r, "/bookings", "Booking cancelled.")
}

// handleMyBookings renders the signed-in visitor's own bookings across every event, each with a
// scannable QR code ticket and a Cancel action (confirmed/waitlisted only).
func (a *App) handleMyBookings(w http.ResponseWriter, r *http.Request) {
	data := sessionFrom(r)
	token := data.AccessToken()

	bookings, err := a.bookings.MyBookings(r.Context(), token, data.UserID())
	if err != nil {
		a.serverError(w, r, err)
		return
	}

	views := make([]BookingView, 0, len(bookings))
	for _, booking := range bookings {
		event, err := a.events.ByID(r.Context(), token, booking.EventID)
		if err != nil {
			// The event this booking belongs to may have been deleted since - skip it rather than
			// failing the whole page for one stale row.
			continue
		}
		views = append(views, buildBookingView(booking, event))
	}

	view := MyBookingsPageData{
		Base:     a.baseView(r, "My bookings"),
		Bookings: views,
	}
	view.FlashError, view.FlashSuccess = flashFromQuery(r)
	a.render(w, r, http.StatusOK, "bookings.html", view)
}
