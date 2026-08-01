package dev.mudbase.showcase.events.domain;

import dev.mudbase.showcase.events.mudbase.DocumentMapper;
import dev.mudbase.showcase.events.support.Formatting;
import java.util.Map;

/** Mirrors the `events` collection - see plan/build-plan.md. */
public class EventDoc {

  private final String id;
  private final String title;
  private final String description;
  private final String startsAt;
  private final String location;
  private final int capacity;
  private final String organizerId;
  private final String organizerName;
  private final String createdAt;

  private EventDoc(
      String id,
      String title,
      String description,
      String startsAt,
      String location,
      int capacity,
      String organizerId,
      String organizerName,
      String createdAt) {
    this.id = id;
    this.title = title;
    this.description = description;
    this.startsAt = startsAt;
    this.location = location;
    this.capacity = capacity;
    this.organizerId = organizerId;
    this.organizerName = organizerName;
    this.createdAt = createdAt;
  }

  public static EventDoc fromDocument(Map<String, Object> doc) {
    return new EventDoc(
        DocumentMapper.getId(doc),
        DocumentMapper.getString(doc, "title", "Untitled event"),
        DocumentMapper.getString(doc, "description"),
        DocumentMapper.getString(doc, "startsAt"),
        DocumentMapper.getString(doc, "location", ""),
        DocumentMapper.getInt(doc, "capacity", 0),
        DocumentMapper.getString(doc, "organizerId"),
        DocumentMapper.getString(doc, "organizerName", "Someone"),
        DocumentMapper.getString(doc, "createdAt"));
  }

  public String getId() {
    return id;
  }

  public String getTitle() {
    return title;
  }

  public String getDescription() {
    return description;
  }

  public boolean isHasDescription() {
    return description != null && !description.isBlank();
  }

  public String getStartsAt() {
    return startsAt;
  }

  /** Pre-fill value for an HTML `<input type="datetime-local">` when editing this event. */
  public String getStartsAtLocalInputValue() {
    return Formatting.toDateTimeLocalValue(startsAt);
  }

  public String getFormattedStartsAt() {
    return Formatting.formatDateTime(startsAt);
  }

  public String getLocation() {
    return location;
  }

  public int getCapacity() {
    return capacity;
  }

  public String getOrganizerId() {
    return organizerId;
  }

  public String getOrganizerName() {
    return organizerName;
  }

  public String getCreatedAt() {
    return createdAt;
  }

  public boolean isOwnedBy(String userId) {
    return userId != null && userId.equals(organizerId);
  }
}
