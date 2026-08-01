package dev.mudbase.showcase.events.domain;

import dev.mudbase.showcase.events.mudbase.DocumentMapper;
import dev.mudbase.showcase.events.support.Formatting;
import java.util.Map;

/** Mirrors the `bookings` collection - see plan/build-plan.md. */
public class BookingDoc {

  public static final String CONFIRMED = "confirmed";
  public static final String WAITLISTED = "waitlisted";
  public static final String CANCELLED = "cancelled";
  public static final String CHECKED_IN = "checked_in";

  private final String id;
  private final String eventId;
  private final String userId;
  private final String userName;
  private final String status;
  private final String qrToken;
  private final String createdAt;

  private BookingDoc(
      String id, String eventId, String userId, String userName, String status, String qrToken, String createdAt) {
    this.id = id;
    this.eventId = eventId;
    this.userId = userId;
    this.userName = userName;
    this.status = status;
    this.qrToken = qrToken;
    this.createdAt = createdAt;
  }

  public static BookingDoc fromDocument(Map<String, Object> doc) {
    return new BookingDoc(
        DocumentMapper.getId(doc),
        DocumentMapper.getString(doc, "eventId"),
        DocumentMapper.getString(doc, "userId"),
        DocumentMapper.getString(doc, "userName", "Someone"),
        DocumentMapper.getString(doc, "status", WAITLISTED),
        DocumentMapper.getString(doc, "qrToken", ""),
        DocumentMapper.getString(doc, "createdAt"));
  }

  public String getId() {
    return id;
  }

  public String getEventId() {
    return eventId;
  }

  public String getUserId() {
    return userId;
  }

  public String getUserName() {
    return userName;
  }

  public String getStatus() {
    return status;
  }

  public String getQrToken() {
    return qrToken;
  }

  public String getCreatedAt() {
    return createdAt;
  }

  public boolean isOwnedBy(String userId) {
    return userId != null && userId.equals(this.userId);
  }

  public boolean isCancellable() {
    return CONFIRMED.equals(status) || WAITLISTED.equals(status);
  }

  public boolean isCancelled() {
    return CANCELLED.equals(status);
  }

  public String getStatusLabel() {
    return switch (status) {
      case CONFIRMED -> "Confirmed";
      case WAITLISTED -> "Waitlisted";
      case CHECKED_IN -> "Checked in";
      case CANCELLED -> "Cancelled";
      default -> status;
    };
  }

  public String getFormattedCreatedAt() {
    return Formatting.formatDateTime(createdAt);
  }
}
