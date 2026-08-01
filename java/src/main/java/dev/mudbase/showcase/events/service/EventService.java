package dev.mudbase.showcase.events.service;

import dev.mudbase.showcase.events.auth.AuthSession;
import dev.mudbase.showcase.events.config.MudbaseProperties;
import dev.mudbase.showcase.events.domain.EventDoc;
import dev.mudbase.showcase.events.mudbase.MudbaseApiException;
import dev.mudbase.showcase.events.mudbase.MudbaseDataClient;
import dev.mudbase.showcase.events.mudbase.PageResult;
import dev.mudbase.showcase.events.support.EventNotFoundException;
import dev.mudbase.showcase.events.support.ForbiddenActionException;
import dev.mudbase.showcase.events.support.Formatting;
import dev.mudbase.showcase.events.support.RoleSupport;
import dev.mudbase.showcase.events.web.dto.EventFormRequest;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import org.springframework.stereotype.Service;

/**
 * Reads and writes the `events` collection. Creation is organizer-role-gated; editing/deleting is
 * additionally ownership-gated (only the organizer who created a given event may change it) -
 * both checked with {@link RoleSupport}/{@link EventDoc#isOwnedBy} before any mutating Mudbase
 * call is attempted, per {@link ForbiddenActionException}'s javadoc.
 */
@Service
public class EventService {

  private static final int EVENTS_PAGE_SIZE = 10;

  private final MudbaseDataClient dataClient;
  private final MudbaseProperties properties;
  private final ActivityService activityService;

  public EventService(MudbaseDataClient dataClient, MudbaseProperties properties, ActivityService activityService) {
    this.dataClient = dataClient;
    this.properties = properties;
    this.activityService = activityService;
  }

  /** Paginated event list, ascending by start time - mirrors the reference web app's `useEvents`. */
  public PageResult<EventDoc> listEvents(String bearerToken, int page) {
    PageResult<Map<String, Object>> raw =
        dataClient.listPage(bearerToken, properties.getEventsCollectionId(), Map.of(), "startsAt", page, EVENTS_PAGE_SIZE);
    return new PageResult<>(raw.items().stream().map(EventDoc::fromDocument).toList(), raw.page(), raw.limit(), raw.total(), raw.hasMore());
  }

  public Optional<EventDoc> findById(String bearerToken, String eventId) {
    try {
      return Optional.of(EventDoc.fromDocument(dataClient.get(bearerToken, properties.getEventsCollectionId(), eventId)));
    } catch (MudbaseApiException e) {
      return Optional.empty();
    }
  }

  /** The live confirmed-booking count for one event, for the capacity indicator on its card/detail. */
  public long confirmedCount(String bearerToken, String eventId) {
    return dataClient.count(
        bearerToken, properties.getBookingsCollectionId(), Map.of("eventId", eventId, "status", "confirmed"));
  }

  /** Organizer-only: creates a new event owned by the acting organizer. */
  public EventDoc createEvent(AuthSession actor, EventFormRequest form) {
    requireOrganizerRole(actor, "create an event");

    Map<String, Object> body = new LinkedHashMap<>();
    body.put("title", form.getTitle().trim());
    if (form.getDescription() != null && !form.getDescription().isBlank()) {
      body.put("description", form.getDescription().trim());
    }
    body.put("startsAt", Formatting.parseDateTimeLocalToIso(form.getStartsAt()));
    body.put("location", form.getLocation().trim());
    body.put("capacity", form.getCapacity());
    body.put("organizerId", actor.getUserId());
    body.put("organizerName", actor.getDisplayName());

    EventDoc created = EventDoc.fromDocument(dataClient.create(actor.getToken(), properties.getEventsCollectionId(), body));
    activityService.record(actor.getToken(), created.getId(), actor.getUserId(), actor.getDisplayName(), "event_created");
    return created;
  }

  /** Organizer-only, own-event-only: edits an existing event in place. */
  public EventDoc updateEvent(AuthSession actor, String eventId, EventFormRequest form) {
    EventDoc existing = requireExisting(actor.getToken(), eventId);
    requireOwnedByOrganizer(actor, existing, "edit this event");

    Map<String, Object> body = new LinkedHashMap<>();
    body.put("title", form.getTitle().trim());
    body.put("description", form.getDescription() != null ? form.getDescription().trim() : "");
    body.put("startsAt", Formatting.parseDateTimeLocalToIso(form.getStartsAt()));
    body.put("location", form.getLocation().trim());
    body.put("capacity", form.getCapacity());

    EventDoc updated = EventDoc.fromDocument(dataClient.update(actor.getToken(), properties.getEventsCollectionId(), eventId, body));
    activityService.record(actor.getToken(), eventId, actor.getUserId(), actor.getDisplayName(), "event_updated");
    return updated;
  }

  /** Organizer-only, own-event-only: deletes an event. Does not cascade to its bookings/activity rows, matching the reference web app's `useDeleteEvent`. */
  public void deleteEvent(AuthSession actor, String eventId) {
    EventDoc existing = requireExisting(actor.getToken(), eventId);
    requireOwnedByOrganizer(actor, existing, "delete this event");
    dataClient.delete(actor.getToken(), properties.getEventsCollectionId(), eventId);
  }

  /** Fetches an event or throws {@link EventNotFoundException} - shared by controllers/services that need a hard failure rather than an {@code Optional}. */
  public EventDoc requireExisting(String bearerToken, String eventId) {
    return findById(bearerToken, eventId).orElseThrow(() -> new EventNotFoundException(eventId));
  }

  /** Public so {@link dev.mudbase.showcase.events.service.BookingService} can reuse the same ownership check for check-in. */
  public void requireOwnedByOrganizer(AuthSession actor, EventDoc event, String action) {
    if (!RoleSupport.isOrganizer(actor.getRole()) || !event.isOwnedBy(actor.getUserId())) {
      throw new ForbiddenActionException("Only this event's organizer can " + action + ".");
    }
  }

  private void requireOrganizerRole(AuthSession actor, String action) {
    if (!RoleSupport.isOrganizer(actor.getRole())) {
      throw new ForbiddenActionException("Only an organizer can " + action + ".");
    }
  }
}
