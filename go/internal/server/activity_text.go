package server

import (
	"fmt"

	"github.com/mudbase/mudbase-showcase-events/go/internal/models"
)

// describeActivity renders one activity row as a plain, readable sentence for the event's feed.
func describeActivity(entry models.Activity) string {
	who := entry.ActorName
	if who == "" {
		who = "Someone"
	}

	switch entry.Action {
	case models.ActionBookingConfirmed:
		return fmt.Sprintf("%s booked a confirmed spot", who)
	case models.ActionBookingWaitlisted:
		return fmt.Sprintf("%s was added to the waitlist", who)
	case models.ActionBookingCancelled:
		return fmt.Sprintf("%s cancelled their booking", who)
	case models.ActionBookingPromoted:
		return fmt.Sprintf("%s was promoted from the waitlist to confirmed", who)
	case models.ActionCheckedIn:
		return fmt.Sprintf("%s checked in", who)
	case models.ActionEventCreated:
		return fmt.Sprintf("%s created this event", who)
	case models.ActionEventUpdated:
		return fmt.Sprintf("%s updated this event", who)
	default:
		return fmt.Sprintf("%s did something on this event", who)
	}
}
