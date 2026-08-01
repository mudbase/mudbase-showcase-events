package dev.mudbase.showcase.events.domain;

import dev.mudbase.showcase.events.mudbase.DocumentMapper;
import dev.mudbase.showcase.events.support.Formatting;
import java.util.Map;

/**
 * Mirrors the `activity` collection - see plan/build-plan.md. {@link #getDescription()} mirrors
 * the reference web app's {@code ACTIVITY_LABELS} map (../web/src/types/activity.ts) sentence-for-
 * sentence.
 */
public class ActivityEntry {

  private final String id;
  private final String eventId;
  private final String actorId;
  private final String actorName;
  private final String action;
  private final String createdAt;

  private ActivityEntry(
      String id, String eventId, String actorId, String actorName, String action, String createdAt) {
    this.id = id;
    this.eventId = eventId;
    this.actorId = actorId;
    this.actorName = actorName;
    this.action = action;
    this.createdAt = createdAt;
  }

  public static ActivityEntry fromDocument(Map<String, Object> doc) {
    return new ActivityEntry(
        DocumentMapper.getId(doc),
        DocumentMapper.getString(doc, "eventId"),
        DocumentMapper.getString(doc, "actorId"),
        DocumentMapper.getString(doc, "actorName", "Someone"),
        DocumentMapper.getString(doc, "action", ""),
        DocumentMapper.getString(doc, "createdAt"));
  }

  public String getId() {
    return id;
  }

  public String getEventId() {
    return eventId;
  }

  public String getActorId() {
    return actorId;
  }

  public String getActorName() {
    return actorName;
  }

  public String getAction() {
    return action;
  }

  public String getCreatedAt() {
    return createdAt;
  }

  public String getFormattedCreatedAt() {
    return Formatting.formatRelativeTime(createdAt);
  }

  /** Mirrors ../web/src/types/activity.ts `ACTIVITY_LABELS` exactly. */
  public String getDescription() {
    return switch (action) {
      case "booking_confirmed" -> "booked (confirmed)";
      case "booking_waitlisted" -> "joined the waitlist";
      case "booking_cancelled" -> "cancelled their booking";
      case "booking_promoted" -> "was promoted from the waitlist";
      case "checked_in" -> "checked in";
      case "event_created" -> "created this event";
      case "event_updated" -> "updated this event";
      default -> action;
    };
  }
}
