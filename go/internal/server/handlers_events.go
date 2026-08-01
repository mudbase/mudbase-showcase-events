package server

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/mudbase/mudbase-showcase-events/go/internal/models"
	"github.com/mudbase/mudbase-showcase-events/go/internal/store"
)

// Field length/range caps mirror the reference web app's EventForm zod schema
// (../web/src/components/events/EventForm.tsx eventFormSchema).
const (
	eventTitleMaxLen       = 200
	eventDescriptionMaxLen = 2000
	eventLocationMaxLen    = 200
	eventCapacityMin       = 1
	eventCapacityMax       = 100000
)

// handleEventList renders the paginated event list, soonest-starting first, each card showing a
// live confirmed-vs-capacity indicator. Every signed-in role can read it - see
// plan/build-plan.md "RBAC Matrix".
func (a *App) handleEventList(w http.ResponseWriter, r *http.Request) {
	page := int32(1)
	if p, err := strconv.Atoi(r.URL.Query().Get("page")); err == nil && p > 0 {
		page = int32(p)
	}

	data := sessionFrom(r)
	token := data.AccessToken()

	paged, err := a.events.List(r.Context(), token, page)
	if err != nil {
		a.serverError(w, r, err)
		return
	}

	cards := make([]EventCardView, 0, len(paged.Events))
	for _, event := range paged.Events {
		confirmedCount, err := a.bookings.ConfirmedCount(r.Context(), token, event.ID)
		if err != nil {
			a.serverError(w, r, err)
			return
		}
		cards = append(cards, buildEventCardView(event, confirmedCount, data.UserID()))
	}

	view := EventListPageData{
		Base:       a.baseView(r, "Events"),
		Events:     cards,
		Page:       paged.Page,
		TotalPages: paged.TotalPages,
		HasPrev:    paged.Page > 1,
		HasNext:    paged.Page < paged.TotalPages,
	}
	view.FlashError, view.FlashSuccess = flashFromQuery(r)
	a.render(w, r, http.StatusOK, "events_list.html", view)
}

// handleEventNewShow renders the organizer-only create-event form. Route already gated by
// requireOrganizer.
func (a *App) handleEventNewShow(w http.ResponseWriter, r *http.Request) {
	view := EventFormPageData{
		Base:   a.baseView(r, "New event"),
		IsEdit: false,
	}
	view.FlashError, view.FlashSuccess = flashFromQuery(r)
	a.render(w, r, http.StatusOK, "event_new.html", view)
}

// parseEventForm validates and extracts the shared create/edit event form fields, returning a
// human-readable validation error message (empty when valid).
func parseEventForm(r *http.Request) (title, description, location string, startsAtISO string, capacity int, validationErr string) {
	title = strings.TrimSpace(r.FormValue("title"))
	description = strings.TrimSpace(r.FormValue("description"))
	location = strings.TrimSpace(r.FormValue("location"))
	startsAtLocal := r.FormValue("startsAt")

	if title == "" {
		return "", "", "", "", 0, "Title is required."
	}
	if len(title) > eventTitleMaxLen {
		return "", "", "", "", 0, "Title is too long."
	}
	if len(description) > eventDescriptionMaxLen {
		return "", "", "", "", 0, "Description is too long."
	}
	if location == "" {
		return "", "", "", "", 0, "Location is required."
	}
	if len(location) > eventLocationMaxLen {
		return "", "", "", "", 0, "Location is too long."
	}
	if startsAtLocal == "" {
		return "", "", "", "", 0, "Date and time is required."
	}
	startsAtISO = datetimeLocalToISO(startsAtLocal)
	if startsAtISO == "" {
		return "", "", "", "", 0, "Enter a valid date and time."
	}

	capacityStr := r.FormValue("capacity")
	parsedCapacity, err := strconv.Atoi(capacityStr)
	if err != nil {
		return "", "", "", "", 0, "Capacity must be a whole number."
	}
	if parsedCapacity < eventCapacityMin {
		return "", "", "", "", 0, "Capacity must be at least 1."
	}
	if parsedCapacity > eventCapacityMax {
		return "", "", "", "", 0, "Capacity is unrealistically large."
	}

	return title, description, location, startsAtISO, parsedCapacity, ""
}

// handleEventNewSubmit creates a new event. Route already gated by requireOrganizer (owner-only,
// per the RBAC matrix - every organizer account may create/edit/delete/check-in on any event).
func (a *App) handleEventNewSubmit(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		a.serverError(w, r, err)
		return
	}
	title, description, location, startsAtISO, capacity, validationErr := parseEventForm(r)
	if validationErr != "" {
		redirectWithError(w, r, "/events/new", validationErr)
		return
	}

	data := sessionFrom(r)
	event, err := a.events.Create(r.Context(), data.AccessToken(), data.UserID(), data.DisplayName(), store.CreateInput{
		Title:       title,
		Description: description,
		StartsAt:    startsAtISO,
		Location:    location,
		Capacity:    capacity,
	})
	if err != nil {
		mutationError(w, r, "/events/new", err, "Couldn't create that event. Please try again.")
		return
	}

	http.Redirect(w, r, "/events/"+event.ID, http.StatusSeeOther)
}

// eventDetailView loads everything the /events/{id} page needs: the event itself, its live
// confirmed count, the viewer's own booking (if any), and its activity feed.
func (a *App) eventDetailView(r *http.Request, eventID string) (EventDetailPageData, error) {
	data := sessionFrom(r)
	token := data.AccessToken()

	event, err := a.events.ByID(r.Context(), token, eventID)
	if err != nil {
		return EventDetailPageData{}, err
	}

	confirmedCount, err := a.bookings.ConfirmedCount(r.Context(), token, event.ID)
	if err != nil {
		return EventDetailPageData{}, err
	}

	entries, err := a.activity.Feed(r.Context(), token, event.ID)
	if err != nil {
		return EventDetailPageData{}, err
	}

	isOwnEvent := data.UserID() != "" && event.OrganizerID == data.UserID()

	view := EventDetailPageData{
		Base:               a.baseView(r, event.Title),
		Event:              event,
		StartsAtLabel:      formatDateTime(event.StartsAt),
		CapacityLabel:      formatCapacityLabel(confirmedCount, event.Capacity),
		IsFull:             confirmedCount >= event.Capacity,
		IsOrganizerOfEvent: isOwnEvent,
		Activity:           buildActivityView(entries),
	}

	if data.IsSignedIn() && !isOwnEvent {
		booking, found, err := a.bookings.MyBookingForEvent(r.Context(), token, event.ID, data.UserID())
		if err != nil {
			return EventDetailPageData{}, err
		}
		if found {
			bv := buildBookingView(booking, event)
			view.MyBooking = &bv
			view.CanBook = booking.Status == models.StatusCancelled
		} else {
			view.CanBook = true
		}
	}

	return view, nil
}

func formatCapacityLabel(confirmedCount, capacity int) string {
	return strconv.Itoa(confirmedCount) + " / " + strconv.Itoa(capacity)
}

// handleEventDetail renders the full event detail page: info, capacity indicator, Book button (for
// a signed-in non-organizer viewer), organizer-only Edit/Delete/Check-in affordances (gated on
// `organizerId === session.user.id` - a UX-only refinement layered on top of Mudbase's coarser
// role-level permission, see plan/build-plan.md "RBAC Matrix"), and the reverse-chronological
// activity feed.
func (a *App) handleEventDetail(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	view, err := a.eventDetailView(r, id)
	if err != nil {
		redirectWithError(w, r, "/", "That event couldn't be found.")
		return
	}
	view.FlashError, view.FlashSuccess = flashFromQuery(r)
	a.render(w, r, http.StatusOK, "event_detail.html", view)
}

// handleEventEditShow renders the organizer-only edit-event form, pre-filled with the event's
// current values. Route already gated by requireOrganizer.
func (a *App) handleEventEditShow(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	data := sessionFrom(r)

	event, err := a.events.ByID(r.Context(), data.AccessToken(), id)
	if err != nil {
		redirectWithError(w, r, "/", "That event couldn't be found.")
		return
	}

	view := EventFormPageData{
		Base:          a.baseView(r, "Edit "+event.Title),
		Event:         event,
		StartsAtLocal: toDateTimeLocalValue(event.StartsAt),
		IsEdit:        true,
	}
	view.FlashError, view.FlashSuccess = flashFromQuery(r)
	a.render(w, r, http.StatusOK, "event_edit.html", view)
}

// handleEventEditSubmit saves edits to an existing event. Route already gated by requireOrganizer.
func (a *App) handleEventEditSubmit(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if err := r.ParseForm(); err != nil {
		a.serverError(w, r, err)
		return
	}
	backPath := "/events/" + id + "/edit"
	title, description, location, startsAtISO, capacity, validationErr := parseEventForm(r)
	if validationErr != "" {
		redirectWithError(w, r, backPath, validationErr)
		return
	}

	data := sessionFrom(r)
	if _, err := a.events.Update(r.Context(), data.AccessToken(), data.UserID(), data.DisplayName(), id, store.UpdateInput{
		Title:       title,
		Description: description,
		StartsAt:    startsAtISO,
		Location:    location,
		Capacity:    capacity,
	}); err != nil {
		mutationError(w, r, backPath, err, "Couldn't save those changes. Please try again.")
		return
	}

	http.Redirect(w, r, "/events/"+id, http.StatusSeeOther)
}

// handleEventDelete deletes an event. Route already gated by requireOrganizer.
func (a *App) handleEventDelete(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	data := sessionFrom(r)

	if err := a.events.Delete(r.Context(), data.AccessToken(), id); err != nil {
		mutationError(w, r, "/events/"+id, err, "Couldn't delete that event. Please try again.")
		return
	}

	http.Redirect(w, r, "/", http.StatusSeeOther)
}
