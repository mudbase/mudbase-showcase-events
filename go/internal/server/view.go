package server

import (
	"fmt"
	"net/http"

	"github.com/mudbase/mudbase-showcase-events/go/internal/models"
	"github.com/mudbase/mudbase-showcase-events/go/internal/rbac"
)

// Base holds the fields every page's layout needs (header nav, role badge, flash banner). It is
// embedded in every page-specific data struct so templates can read `.IsSignedIn`, `.Flash`, etc.
// directly at the top level via Go's promoted-field rules.
type Base struct {
	Title           string
	IsSignedIn      bool
	UserID          string
	DisplayName     string
	Role            string
	RoleLabel       string
	CanManageEvents bool
	FlashError      string
	FlashSuccess    string
}

// baseView builds the Base fields shared by every page from the current request's session.
func (a *App) baseView(r *http.Request, title string) Base {
	data := sessionFrom(r)
	return Base{
		Title:           title,
		IsSignedIn:      data.IsSignedIn(),
		UserID:          data.UserID(),
		DisplayName:     data.DisplayName(),
		Role:            data.Role(),
		RoleLabel:       rbac.Label(data.Role()),
		CanManageEvents: rbac.CanManageEvents(data.Role()),
	}
}

// EventCardView is a display-ready event for the list page.
type EventCardView struct {
	models.Event
	StartsAtLabel string
	CapacityLabel string
	IsFull        bool
	IsOwnEvent    bool
}

func buildEventCardView(event models.Event, confirmedCount int, viewerUserID string) EventCardView {
	return EventCardView{
		Event:         event,
		StartsAtLabel: formatDateTime(event.StartsAt),
		CapacityLabel: fmt.Sprintf("%d / %d", confirmedCount, event.Capacity),
		IsFull:        confirmedCount >= event.Capacity,
		IsOwnEvent:    viewerUserID != "" && event.OrganizerID == viewerUserID,
	}
}

// EventListPageData is the / page's content payload.
type EventListPageData struct {
	Base
	Events     []EventCardView
	Page       int32
	TotalPages int32
	HasPrev    bool
	HasNext    bool
}

// BookingView is a display-ready booking, used both on the event detail page (the viewer's own
// booking for that event) and the /bookings page (every booking the viewer holds).
type BookingView struct {
	models.Booking
	EventTitle         string
	EventStartsAtLabel string
	EventLocation      string
	StatusLabel        string
	StatusClass        string
	QRDataURI          string
	CanCancel          bool
}

// statusLabel and statusClass render a BookingStatus for display - a plain word plus a CSS class
// suffix the stylesheet uses for color-coding (see static/style.css ".status-badge-*").
func statusLabel(status models.BookingStatus) string {
	switch status {
	case models.StatusConfirmed:
		return "Confirmed"
	case models.StatusWaitlisted:
		return "Waitlisted"
	case models.StatusCancelled:
		return "Cancelled"
	case models.StatusCheckedIn:
		return "Checked in"
	default:
		return "Unknown"
	}
}

func statusClass(status models.BookingStatus) string {
	switch status {
	case models.StatusConfirmed:
		return "confirmed"
	case models.StatusWaitlisted:
		return "waitlisted"
	case models.StatusCancelled:
		return "cancelled"
	case models.StatusCheckedIn:
		return "checked-in"
	default:
		return "unknown"
	}
}

func buildBookingView(booking models.Booking, event models.Event) BookingView {
	return BookingView{
		Booking:            booking,
		EventTitle:         event.Title,
		EventStartsAtLabel: formatDateTime(event.StartsAt),
		EventLocation:      event.Location,
		StatusLabel:        statusLabel(booking.Status),
		StatusClass:        statusClass(booking.Status),
		QRDataURI:          qrDataURI(booking.QRToken),
		CanCancel:          booking.Status == models.StatusConfirmed || booking.Status == models.StatusWaitlisted,
	}
}

// ActivityItemView is a display-ready activity row for an event's feed.
type ActivityItemView struct {
	models.Activity
	Text         string
	CreatedLabel string
}

func buildActivityView(entries []models.Activity) []ActivityItemView {
	views := make([]ActivityItemView, 0, len(entries))
	for _, e := range entries {
		views = append(views, ActivityItemView{
			Activity:     e,
			Text:         describeActivity(e),
			CreatedLabel: formatDateTime(e.CreatedAt),
		})
	}
	return views
}

// EventDetailPageData is the /events/{id} page's content payload.
type EventDetailPageData struct {
	Base
	Event              models.Event
	StartsAtLabel      string
	CapacityLabel      string
	IsFull             bool
	IsOrganizerOfEvent bool
	CanBook            bool
	MyBooking          *BookingView
	Activity           []ActivityItemView
}

// EventFormPageData is the /events/new and /events/{id}/edit pages' shared content payload.
type EventFormPageData struct {
	Base
	Event         models.Event
	StartsAtLocal string
	IsEdit        bool
}

// CheckInPageData is the /events/{id}/checkin page's content payload.
type CheckInPageData struct {
	Base
	Event  models.Event
	Result *CheckInResultView
}

// CheckInResultView is the display-ready outcome of a check-in attempt.
type CheckInResultView struct {
	Message   string
	IsSuccess bool
	Booking   *models.Booking
}

// MyBookingsPageData is the /bookings page's content payload.
type MyBookingsPageData struct {
	Base
	Bookings []BookingView
}
