package server

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/mudbase/mudbase-showcase-events/go/internal/store"
)

// handleCheckInShow renders the organizer-only manual QR-token check-in form for one event. Route
// already gated by requireOrganizer.
func (a *App) handleCheckInShow(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	data := sessionFrom(r)

	event, err := a.events.ByID(r.Context(), data.AccessToken(), id)
	if err != nil {
		redirectWithError(w, r, "/", "That event couldn't be found.")
		return
	}

	view := CheckInPageData{
		Base:  a.baseView(r, "Check in - "+event.Title),
		Event: event,
	}
	a.render(w, r, http.StatusOK, "event_checkin.html", view)
}

// checkInResultView renders one store.CheckInResult as the display-ready message the check-in page
// shows, per the flow documented in ../../web/plan/build-plan.md "Check-In Flow":
//   - no match -> inline error, no mutation
//   - already checked in -> "already checked in" message, no mutation (idempotent)
//   - cancelled -> "this booking was cancelled" message, no mutation
//   - waitlisted -> "this booking is waitlisted, not confirmed" message, no mutation
//   - confirmed -> checked in, success state with the attendee's name
func checkInResultView(result store.CheckInResult) CheckInResultView {
	switch result.Outcome {
	case store.CheckInOutcomeNotFound:
		return CheckInResultView{Message: "No booking found for that check-in code.", IsSuccess: false}
	case store.CheckInOutcomeAlreadyChecked:
		return CheckInResultView{
			Message:   fmt.Sprintf("%s is already checked in.", result.Booking.UserName),
			IsSuccess: false,
			Booking:   &result.Booking,
		}
	case store.CheckInOutcomeCancelled:
		return CheckInResultView{
			Message:   "This booking was cancelled.",
			IsSuccess: false,
			Booking:   &result.Booking,
		}
	case store.CheckInOutcomeWaitlisted:
		return CheckInResultView{
			Message:   "This booking is waitlisted, not confirmed - it can't be checked in yet.",
			IsSuccess: false,
			Booking:   &result.Booking,
		}
	case store.CheckInOutcomeCheckedIn:
		return CheckInResultView{
			Message:   fmt.Sprintf("%s checked in.", result.Booking.UserName),
			IsSuccess: true,
			Booking:   &result.Booking,
		}
	default:
		return CheckInResultView{Message: "Unexpected check-in result.", IsSuccess: false}
	}
}

// handleCheckInSubmit looks up a booking by its pasted/typed qrToken within this event and, if
// eligible, checks it in - see checkInResultView's doc comment for the full outcome mapping. Route
// already gated by requireOrganizer. Renders the result inline (not a redirect) so the outcome and
// attendee name aren't lost to a PRG round-trip.
func (a *App) handleCheckInSubmit(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if err := r.ParseForm(); err != nil {
		a.serverError(w, r, err)
		return
	}
	qrToken := strings.TrimSpace(r.FormValue("qrToken"))

	data := sessionFrom(r)
	token := data.AccessToken()

	event, err := a.events.ByID(r.Context(), token, id)
	if err != nil {
		redirectWithError(w, r, "/", "That event couldn't be found.")
		return
	}

	result, err := a.bookings.CheckIn(r.Context(), token, event.ID, qrToken)
	if err != nil {
		mutationError(w, r, "/events/"+id+"/checkin", err, "Couldn't process that check-in. Please try again.")
		return
	}

	resultView := checkInResultView(result)
	view := CheckInPageData{
		Base:   a.baseView(r, "Check in - "+event.Title),
		Event:  event,
		Result: &resultView,
	}
	a.render(w, r, http.StatusOK, "event_checkin.html", view)
}
