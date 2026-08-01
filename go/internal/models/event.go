// Package models holds this app's typed views of the three Mudbase collections it reads and
// writes (events, bookings, activity) - see plan/build-plan.md for the full schema.
package models

// Event mirrors the `events` Mudbase collection schema.
type Event struct {
	ID            string `json:"_id"`
	CreatedAt     string `json:"createdAt"`
	UpdatedAt     string `json:"updatedAt"`
	Title         string `json:"title"`
	Description   string `json:"description"`
	StartsAt      string `json:"startsAt"`
	Location      string `json:"location"`
	Capacity      int    `json:"capacity"`
	OrganizerID   string `json:"organizerId"`
	OrganizerName string `json:"organizerName"`
}
