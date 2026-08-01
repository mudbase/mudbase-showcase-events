package dev.mudbase.showcase.events.service;

import dev.mudbase.showcase.events.config.MudbaseProperties;
import dev.mudbase.showcase.events.domain.ActivityEntry;
import dev.mudbase.showcase.events.mudbase.MudbaseDataClient;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;

/**
 * Reads and writes the `activity` collection - the per-event audit trail. {@link
 * #record(String, String, String, String, String)} deliberately takes the actor's id/name as
 * explicit parameters rather than deriving them from whichever {@code AuthSession} is currently
 * authenticated: for a waitlist promotion/demotion during capacity reconciliation, and for a
 * check-in, the activity entry's actor is the *guest* the correction/check-in applies to, not the
 * organizer or attendee whose request triggered it - exactly mirroring the reference web app's
 * `reconcileEventCapacity` (../web/src/lib/capacity.ts) and `useCheckIn` (../web/src/hooks/
 * useBookings.ts), which both write `actorId: booking.userId, actorName: booking.userName` using
 * the affected booking's owner, while the *token* used to make the call is still whichever user
 * is currently signed in and triggered the flow.
 */
@Service
public class ActivityService {

  private static final int FEED_LIMIT = 50;

  private final MudbaseDataClient dataClient;
  private final MudbaseProperties properties;

  public ActivityService(MudbaseDataClient dataClient, MudbaseProperties properties) {
    this.dataClient = dataClient;
    this.properties = properties;
  }

  /** Reverse-chronological activity feed for one event. */
  public List<ActivityEntry> feed(String bearerToken, String eventId) {
    return dataClient
        .list(bearerToken, properties.getActivityCollectionId(), Map.of("eventId", eventId), "-createdAt", 1, FEED_LIMIT)
        .stream()
        .map(ActivityEntry::fromDocument)
        .toList();
  }

  /**
   * Appends one row to the activity log. {@code action} is one of {@code booking_confirmed}/
   * {@code booking_waitlisted}/{@code booking_cancelled}/{@code booking_promoted}/{@code
   * checked_in}/{@code event_created}/{@code event_updated} - see {@link
   * ActivityEntry#getDescription()} for how each renders.
   */
  public void record(String bearerToken, String eventId, String actorId, String actorName, String action) {
    Map<String, Object> body = new LinkedHashMap<>();
    body.put("eventId", eventId);
    body.put("actorId", actorId);
    body.put("actorName", actorName);
    body.put("action", action);
    dataClient.create(bearerToken, properties.getActivityCollectionId(), body);
  }
}
