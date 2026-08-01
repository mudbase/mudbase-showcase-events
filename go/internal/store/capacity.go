package store

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/mudbase/mudbase-showcase-events/go/internal/mbase"
	"github.com/mudbase/mudbase-showcase-events/go/internal/models"
)

// reconcileFetchLimit is a generous ceiling on how many live (confirmed+waitlisted) bookings a
// single event can have for reconciliation purposes - well beyond any capacity this demo app's UI
// allows creating, so it never truncates the real data. Ported from the reference web app's
// src/lib/capacity.ts (RECONCILE_FETCH_LIMIT).
const reconcileFetchLimit = 1000

// ReconcileEventCapacity re-derives which bookings for an event should hold a confirmed seat
// versus sit on the waitlist, and patches only the ones whose current status disagrees with that
// derivation.
//
// Mudbase (a generic-CRUD BaaS) has no cross-document transactions or atomic counters, so a plain
// "count confirmed, then create" is inherently racy: two simultaneous booking requests can both
// read the same pre-write count and both decide "there's room". This function narrows that race
// window by re-deriving truth from a fresh read (creation-order priority: the first `capacity`
// bookings, oldest first, among confirmed+waitlisted, are the ones entitled to a seat) and
// correcting any booking that disagrees - whether that means demoting an overshoot back to
// waitlisted, or promoting the earliest waitlisted booking once a cancellation frees a seat.
//
// Deliberately excludes "checked_in" bookings from the capacity count (see
// ../../web/plan/build-plan.md "Capacity-Race Handling Approach") - the task's spec defines
// capacity in terms of `"confirmed"` bookings specifically, and running this after check-in would
// incorrectly free an already-seated attendee's slot for someone else on the waitlist. Ported
// bit-for-bit (algorithmically) from the reference web app's src/lib/capacity.ts
// (reconcileEventCapacity).
func ReconcileEventCapacity(ctx context.Context, client *mbase.Client, bookingsCollectionID string, activity *ActivityService, token, eventID string, capacity int) error {
	confirmedRes, err := mbase.List[models.Booking](ctx, client, token, bookingsCollectionID, mbase.ListParams{
		Filter: map[string]interface{}{"eventId": eventID, "status": string(models.StatusConfirmed)},
		Sort:   "createdAt",
		Limit:  reconcileFetchLimit,
	})
	if err != nil {
		return fmt.Errorf("store: reconciling capacity for event %s: listing confirmed bookings: %w", eventID, err)
	}
	waitlistedRes, err := mbase.List[models.Booking](ctx, client, token, bookingsCollectionID, mbase.ListParams{
		Filter: map[string]interface{}{"eventId": eventID, "status": string(models.StatusWaitlisted)},
		Sort:   "createdAt",
		Limit:  reconcileFetchLimit,
	})
	if err != nil {
		return fmt.Errorf("store: reconciling capacity for event %s: listing waitlisted bookings: %w", eventID, err)
	}

	live := make([]models.Booking, 0, len(confirmedRes.Data)+len(waitlistedRes.Data))
	live = append(live, confirmedRes.Data...)
	live = append(live, waitlistedRes.Data...)
	sort.Slice(live, func(i, j int) bool {
		ti, _ := time.Parse(time.RFC3339, live[i].CreatedAt)
		tj, _ := time.Parse(time.RFC3339, live[j].CreatedAt)
		return ti.Before(tj)
	})

	for index, booking := range live {
		shouldBeConfirmed := index < capacity

		if shouldBeConfirmed && booking.Status != models.StatusConfirmed {
			if _, err := mbase.Update[models.Booking](ctx, client, token, bookingsCollectionID, booking.ID, map[string]interface{}{
				"status": string(models.StatusConfirmed),
			}); err != nil {
				return fmt.Errorf("store: promoting booking %s during reconciliation: %w", booking.ID, err)
			}
			if err := activity.Log(ctx, token, eventID, booking.UserID, booking.UserName, models.ActionBookingPromoted); err != nil {
				return err
			}
		} else if !shouldBeConfirmed && booking.Status != models.StatusWaitlisted {
			if _, err := mbase.Update[models.Booking](ctx, client, token, bookingsCollectionID, booking.ID, map[string]interface{}{
				"status": string(models.StatusWaitlisted),
			}); err != nil {
				return fmt.Errorf("store: demoting booking %s during reconciliation: %w", booking.ID, err)
			}
			if err := activity.Log(ctx, token, eventID, booking.UserID, booking.UserName, models.ActionBookingWaitlisted); err != nil {
				return err
			}
		}
	}

	return nil
}
