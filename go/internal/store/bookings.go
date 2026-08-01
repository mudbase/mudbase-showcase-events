package store

import (
	"context"
	"fmt"

	"github.com/mudbase/mudbase-showcase-events/go/internal/mbase"
	"github.com/mudbase/mudbase-showcase-events/go/internal/models"
)

// myBookingsLimit mirrors the reference web app's useMyBookings limit
// (../web/src/hooks/useBookings.ts).
const myBookingsLimit = 100

// BookingService implements every operation the app needs against the `bookings` collection.
type BookingService struct {
	client       *mbase.Client
	collectionID string
	activity     *ActivityService
}

// NewBookingService builds a BookingService bound to the given bookings collection ID.
func NewBookingService(client *mbase.Client, bookingsCollectionID string, activity *ActivityService) *BookingService {
	return &BookingService{client: client, collectionID: bookingsCollectionID, activity: activity}
}

// ByID fetches a single booking by its Mudbase document ID.
func (s *BookingService) ByID(ctx context.Context, token, id string) (models.Booking, error) {
	booking, err := mbase.Get[models.Booking](ctx, s.client, token, s.collectionID, id)
	if err != nil {
		return models.Booking{}, fmt.Errorf("store: fetching booking %s: %w", id, err)
	}
	return booking, nil
}

// MyBookings returns the signed-in attendee's own bookings across every event, newest first.
func (s *BookingService) MyBookings(ctx context.Context, token, userID string) ([]models.Booking, error) {
	result, err := mbase.List[models.Booking](ctx, s.client, token, s.collectionID, mbase.ListParams{
		Filter: map[string]interface{}{"userId": userID},
		Sort:   "-createdAt",
		Limit:  myBookingsLimit,
	})
	if err != nil {
		return nil, fmt.Errorf("store: listing bookings for user %s: %w", userID, err)
	}
	return result.Data, nil
}

// MyBookingForEvent returns the signed-in user's own booking for one specific event, if any - used
// to hide the Book button / show its status instead.
func (s *BookingService) MyBookingForEvent(ctx context.Context, token, eventID, userID string) (models.Booking, bool, error) {
	result, err := mbase.List[models.Booking](ctx, s.client, token, s.collectionID, mbase.ListParams{
		Filter: map[string]interface{}{"eventId": eventID, "userId": userID},
		Limit:  1,
	})
	if err != nil {
		return models.Booking{}, false, fmt.Errorf("store: fetching booking for event %s / user %s: %w", eventID, userID, err)
	}
	if len(result.Data) == 0 {
		return models.Booking{}, false, nil
	}
	return result.Data[0], true, nil
}

// ConfirmedCount returns the live server-side confirmed-booking count for one event, for the
// capacity indicator on its card/detail page.
func (s *BookingService) ConfirmedCount(ctx context.Context, token, eventID string) (int, error) {
	result, err := mbase.List[models.Booking](ctx, s.client, token, s.collectionID, mbase.ListParams{
		Filter: map[string]interface{}{"eventId": eventID, "status": string(models.StatusConfirmed)},
		Limit:  1,
	})
	if err != nil {
		return 0, fmt.Errorf("store: counting confirmed bookings for event %s: %w", eventID, err)
	}
	return int(result.Total), nil
}

// ByEvent returns every booking for one event (used by the organizer-only check-in lookup and by
// ConfirmedCount's sibling reconciliation pass).
func (s *BookingService) ByEvent(ctx context.Context, token, eventID string) ([]models.Booking, error) {
	result, err := mbase.List[models.Booking](ctx, s.client, token, s.collectionID, mbase.ListParams{
		Filter: map[string]interface{}{"eventId": eventID},
		Sort:   "createdAt",
		Limit:  reconcileFetchLimit,
	})
	if err != nil {
		return nil, fmt.Errorf("store: listing bookings for event %s: %w", eventID, err)
	}
	return result.Data, nil
}

// Create books eventID for the given attendee, using the capacity-race approach documented in
// ../../web/plan/build-plan.md: decide the initial status from a fresh server-side confirmed
// count, write it, then run the shared reconciliation pass so a race against another concurrent
// booking self-corrects. Returns the booking's *post-reconciliation* state, not its tentative
// initial write, so the caller never reports a status that got corrected out from under it a
// moment later. Ported from the reference web app's useCreateBooking.
func (s *BookingService) Create(ctx context.Context, token, eventID string, capacity int, userID, userName string) (models.Booking, error) {
	confirmedCount, err := s.ConfirmedCount(ctx, token, eventID)
	if err != nil {
		return models.Booking{}, err
	}
	initialStatus := models.StatusWaitlisted
	if confirmedCount < capacity {
		initialStatus = models.StatusConfirmed
	}

	qrToken, err := generateQRToken()
	if err != nil {
		return models.Booking{}, err
	}

	booking, err := mbase.Create[models.Booking](ctx, s.client, token, s.collectionID, map[string]interface{}{
		"eventId":  eventID,
		"userId":   userID,
		"userName": userName,
		"status":   string(initialStatus),
		"qrToken":  qrToken,
	})
	if err != nil {
		return models.Booking{}, fmt.Errorf("store: creating booking for event %s: %w", eventID, err)
	}

	confirmedAction := models.ActionBookingWaitlisted
	if initialStatus == models.StatusConfirmed {
		confirmedAction = models.ActionBookingConfirmed
	}
	if err := s.activity.Log(ctx, token, eventID, userID, userName, confirmedAction); err != nil {
		return models.Booking{}, err
	}

	if err := ReconcileEventCapacity(ctx, s.client, s.collectionID, s.activity, token, eventID, capacity); err != nil {
		return models.Booking{}, err
	}

	// Re-read: reconciliation above may have demoted this exact booking if it lost a race against
	// another concurrent request that also decided "confirmed" from the same pre-write count.
	final, err := mbase.Get[models.Booking](ctx, s.client, token, s.collectionID, booking.ID)
	if err != nil {
		return models.Booking{}, fmt.Errorf("store: re-fetching booking %s after reconciliation: %w", booking.ID, err)
	}
	return final, nil
}

// Cancel cancels an attendee's own booking, then reconciles so the earliest waitlisted booking is
// promoted into the freed seat. Ported from the reference web app's useCancelBooking.
func (s *BookingService) Cancel(ctx context.Context, token, bookingID, eventID string, capacity int, userID, userName string) error {
	if _, err := mbase.Update[models.Booking](ctx, s.client, token, s.collectionID, bookingID, map[string]interface{}{
		"status": string(models.StatusCancelled),
	}); err != nil {
		return fmt.Errorf("store: cancelling booking %s: %w", bookingID, err)
	}

	if err := s.activity.Log(ctx, token, eventID, userID, userName, models.ActionBookingCancelled); err != nil {
		return err
	}

	return ReconcileEventCapacity(ctx, s.client, s.collectionID, s.activity, token, eventID, capacity)
}

// CheckInOutcome enumerates every result CheckIn can produce.
type CheckInOutcome string

const (
	CheckInOutcomeCheckedIn      CheckInOutcome = "checked_in"
	CheckInOutcomeAlreadyChecked CheckInOutcome = "already_checked_in"
	CheckInOutcomeCancelled      CheckInOutcome = "cancelled"
	CheckInOutcomeWaitlisted     CheckInOutcome = "waitlisted"
	CheckInOutcomeNotFound       CheckInOutcome = "not_found"
)

// CheckInResult bundles the outcome and (when found) the matched booking.
type CheckInResult struct {
	Outcome CheckInOutcome
	Booking models.Booking
}

// CheckIn looks up a booking by its scanned/pasted qrToken within one event and, if eligible,
// checks it in. Ported from the reference web app's useCheckIn.
func (s *BookingService) CheckIn(ctx context.Context, token, eventID, qrToken string) (CheckInResult, error) {
	if qrToken == "" {
		return CheckInResult{Outcome: CheckInOutcomeNotFound}, nil
	}

	result, err := mbase.List[models.Booking](ctx, s.client, token, s.collectionID, mbase.ListParams{
		Filter: map[string]interface{}{"eventId": eventID, "qrToken": qrToken},
		Limit:  1,
	})
	if err != nil {
		return CheckInResult{}, fmt.Errorf("store: looking up qr token for event %s: %w", eventID, err)
	}
	if len(result.Data) == 0 {
		return CheckInResult{Outcome: CheckInOutcomeNotFound}, nil
	}
	booking := result.Data[0]

	switch booking.Status {
	case models.StatusCheckedIn:
		return CheckInResult{Outcome: CheckInOutcomeAlreadyChecked, Booking: booking}, nil
	case models.StatusCancelled:
		return CheckInResult{Outcome: CheckInOutcomeCancelled, Booking: booking}, nil
	case models.StatusWaitlisted:
		return CheckInResult{Outcome: CheckInOutcomeWaitlisted, Booking: booking}, nil
	}

	updated, err := mbase.Update[models.Booking](ctx, s.client, token, s.collectionID, booking.ID, map[string]interface{}{
		"status": string(models.StatusCheckedIn),
	})
	if err != nil {
		return CheckInResult{}, fmt.Errorf("store: checking in booking %s: %w", booking.ID, err)
	}
	if err := s.activity.Log(ctx, token, eventID, booking.UserID, booking.UserName, models.ActionCheckedIn); err != nil {
		return CheckInResult{}, err
	}
	return CheckInResult{Outcome: CheckInOutcomeCheckedIn, Booking: updated}, nil
}
