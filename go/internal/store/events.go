package store

import (
	"context"
	"fmt"

	"github.com/mudbase/mudbase-showcase-events/go/internal/mbase"
	"github.com/mudbase/mudbase-showcase-events/go/internal/models"
)

// eventsPageSize mirrors the reference web app's EVENTS_PAGE_SIZE (../web/src/hooks/useEvents.ts).
const eventsPageSize = 10

// EventService implements every operation the app needs against the `events` collection.
type EventService struct {
	client       *mbase.Client
	collectionID string
	activity     *ActivityService
}

// NewEventService builds an EventService bound to the given events collection ID.
func NewEventService(client *mbase.Client, eventsCollectionID string, activity *ActivityService) *EventService {
	return &EventService{client: client, collectionID: eventsCollectionID, activity: activity}
}

// PagedEvents is one page of events plus the pagination metadata the list page's "next/prev"
// controls need.
type PagedEvents struct {
	Events     []models.Event
	Page       int32
	Limit      int32
	Total      int32
	TotalPages int32
}

// List returns one page of events, soonest-starting first (sort: "startsAt"), matching the
// reference web app's useEvents(page).
func (s *EventService) List(ctx context.Context, token string, page int32) (PagedEvents, error) {
	if page < 1 {
		page = 1
	}
	result, err := mbase.List[models.Event](ctx, s.client, token, s.collectionID, mbase.ListParams{
		Sort:  "startsAt",
		Page:  page,
		Limit: eventsPageSize,
	})
	if err != nil {
		return PagedEvents{}, fmt.Errorf("store: listing events: %w", err)
	}
	return PagedEvents{
		Events:     result.Data,
		Page:       result.Page,
		Limit:      result.Limit,
		Total:      result.Total,
		TotalPages: result.TotalPages,
	}, nil
}

// ByID fetches a single event by its Mudbase document ID.
func (s *EventService) ByID(ctx context.Context, token, id string) (models.Event, error) {
	event, err := mbase.Get[models.Event](ctx, s.client, token, s.collectionID, id)
	if err != nil {
		return models.Event{}, fmt.Errorf("store: fetching event %s: %w", id, err)
	}
	return event, nil
}

// CreateInput bundles a new event's user-supplied fields.
type CreateInput struct {
	Title       string
	Description string
	StartsAt    string
	Location    string
	Capacity    int
}

// Create adds a new event and logs an event_created activity row. Organizer-only - enforced by
// internal/server/middleware.go's requireOrganizer before this is ever called, and independently
// by Mudbase's own collection permissions server-side.
func (s *EventService) Create(ctx context.Context, token, organizerID, organizerName string, input CreateInput) (models.Event, error) {
	body := map[string]interface{}{
		"title":         input.Title,
		"startsAt":      input.StartsAt,
		"location":      input.Location,
		"capacity":      input.Capacity,
		"organizerId":   organizerID,
		"organizerName": organizerName,
	}
	if input.Description != "" {
		body["description"] = input.Description
	}

	created, err := mbase.Create[models.Event](ctx, s.client, token, s.collectionID, body)
	if err != nil {
		return models.Event{}, fmt.Errorf("store: creating event: %w", err)
	}

	if err := s.activity.Log(ctx, token, created.ID, organizerID, organizerName, models.ActionEventCreated); err != nil {
		return models.Event{}, err
	}
	return created, nil
}

// UpdateInput bundles an event edit's user-supplied fields.
type UpdateInput struct {
	Title       string
	Description string
	StartsAt    string
	Location    string
	Capacity    int
}

// Update edits an event in place and logs an event_updated activity row. Organizer-only.
func (s *EventService) Update(ctx context.Context, token, actorID, actorName, eventID string, input UpdateInput) (models.Event, error) {
	updated, err := mbase.Update[models.Event](ctx, s.client, token, s.collectionID, eventID, map[string]interface{}{
		"title":       input.Title,
		"description": input.Description,
		"startsAt":    input.StartsAt,
		"location":    input.Location,
		"capacity":    input.Capacity,
	})
	if err != nil {
		return models.Event{}, fmt.Errorf("store: updating event %s: %w", eventID, err)
	}

	if err := s.activity.Log(ctx, token, eventID, actorID, actorName, models.ActionEventUpdated); err != nil {
		return models.Event{}, err
	}
	return updated, nil
}

// Delete removes an event. Organizer-only. Not itself logged to the activity feed - matches the
// reference web app's useDeleteEvent (there is no "event_deleted" ActivityAction).
func (s *EventService) Delete(ctx context.Context, token, eventID string) error {
	if err := mbase.Delete(ctx, s.client, token, s.collectionID, eventID); err != nil {
		return fmt.Errorf("store: deleting event %s: %w", eventID, err)
	}
	return nil
}
