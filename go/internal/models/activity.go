package models

// ActivityAction enumerates every value this app writes to `activity.action`, matching the
// reference web app's src/lib/capacity.ts and src/hooks/useBookings.ts exactly (see
// plan/build-plan.md "Data Models").
type ActivityAction string

const (
	ActionBookingConfirmed  ActivityAction = "booking_confirmed"
	ActionBookingWaitlisted ActivityAction = "booking_waitlisted"
	ActionBookingCancelled  ActivityAction = "booking_cancelled"
	ActionBookingPromoted   ActivityAction = "booking_promoted"
	ActionCheckedIn         ActivityAction = "checked_in"
	ActionEventCreated      ActivityAction = "event_created"
	ActionEventUpdated      ActivityAction = "event_updated"
)

// Activity mirrors the `activity` Mudbase collection schema - one reverse-chronological log row.
type Activity struct {
	ID        string         `json:"_id"`
	CreatedAt string         `json:"createdAt"`
	EventID   string         `json:"eventId"`
	ActorID   string         `json:"actorId"`
	ActorName string         `json:"actorName"`
	Action    ActivityAction `json:"action"`
}
