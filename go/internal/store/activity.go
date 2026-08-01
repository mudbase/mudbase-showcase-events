// Package store implements every domain operation this app needs against the three Mudbase
// collections (events, bookings, activity), on top of internal/mbase's generic CRUD helpers. Every
// mutating method here also writes the corresponding `activity` row itself, so a handler can never
// forget to log an action - mirrors the reference web app's src/hooks/useBookings.ts and
// src/lib/capacity.ts, which pair every mutation with an activity write in the same function.
package store

import (
	"context"
	"fmt"

	"github.com/mudbase/mudbase-showcase-events/go/internal/mbase"
	"github.com/mudbase/mudbase-showcase-events/go/internal/models"
)

// feedLimit mirrors the reference web app's useEventActivity FEED_LIMIT
// (../web/src/hooks/useActivity.ts).
const feedLimit = 50

// ActivityService implements every operation the app needs against the `activity` collection.
type ActivityService struct {
	client       *mbase.Client
	collectionID string
}

// NewActivityService builds an ActivityService bound to the given activity collection ID.
func NewActivityService(client *mbase.Client, activityCollectionID string) *ActivityService {
	return &ActivityService{client: client, collectionID: activityCollectionID}
}

// Feed returns the reverse-chronological activity log for one event.
func (s *ActivityService) Feed(ctx context.Context, token, eventID string) ([]models.Activity, error) {
	result, err := mbase.List[models.Activity](ctx, s.client, token, s.collectionID, mbase.ListParams{
		Filter: map[string]interface{}{"eventId": eventID},
		Sort:   "-createdAt",
		Limit:  feedLimit,
	})
	if err != nil {
		return nil, fmt.Errorf("store: listing activity for event %s: %w", eventID, err)
	}
	return result.Data, nil
}

// Log appends one activity row.
func (s *ActivityService) Log(ctx context.Context, token, eventID, actorID, actorName string, action models.ActivityAction) error {
	body := map[string]interface{}{
		"eventId":   eventID,
		"actorId":   actorID,
		"actorName": actorName,
		"action":    string(action),
	}
	if _, err := mbase.Create[models.Activity](ctx, s.client, token, s.collectionID, body); err != nil {
		return fmt.Errorf("store: logging activity %q for event %s: %w", action, eventID, err)
	}
	return nil
}
