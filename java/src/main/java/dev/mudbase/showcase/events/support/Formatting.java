package dev.mudbase.showcase.events.support;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.Locale;

/**
 * Date/time formatting and conversion helpers shared by domain objects, services, and templates -
 * mirrors ../web/src/lib/utils.ts's `formatRelativeTime`, `formatDateTime`, and
 * `toDateTimeLocalValue`.
 */
public final class Formatting {

  private static final DateTimeFormatter DISPLAY_DATE_TIME =
      DateTimeFormatter.ofPattern("MMM d, yyyy, h:mm a", Locale.US);
  private static final DateTimeFormatter DISPLAY_DATE_ONLY = DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US);
  private static final DateTimeFormatter DATETIME_LOCAL_INPUT = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm");

  private Formatting() {}

  /** `Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short" })` equivalent, for event start times. */
  public static String formatDateTime(String iso) {
    if (iso == null || iso.isBlank()) {
      return "";
    }
    try {
      return OffsetDateTime.parse(iso).atZoneSameInstant(ZoneId.systemDefault()).format(DISPLAY_DATE_TIME);
    } catch (DateTimeParseException e) {
      return iso;
    }
  }

  /**
   * A short relative timestamp ("3m", "5h", "2d") for recent activity rows, falling back to an
   * absolute date once something is more than a week old - keeps the activity feed scannable the
   * same way the reference web app's `formatRelativeTime` does.
   */
  public static String formatRelativeTime(String iso) {
    if (iso == null || iso.isBlank()) {
      return "";
    }
    try {
      OffsetDateTime parsed = OffsetDateTime.parse(iso);
      Duration elapsed = Duration.between(parsed.toInstant(), Instant.now());
      if (elapsed.isNegative() || elapsed.toDays() >= 7) {
        return parsed.atZoneSameInstant(ZoneId.systemDefault()).format(DISPLAY_DATE_ONLY);
      }
      if (elapsed.toDays() >= 1) {
        return elapsed.toDays() + "d";
      }
      if (elapsed.toHours() >= 1) {
        return elapsed.toHours() + "h";
      }
      if (elapsed.toMinutes() >= 1) {
        return elapsed.toMinutes() + "m";
      }
      return "just now";
    } catch (DateTimeParseException e) {
      return iso;
    }
  }

  /**
   * Converts an ISO date-time string to the value an HTML `<input type="datetime-local">`
   * expects (local time, no timezone/seconds), for pre-filling the edit-event form. Mirrors
   * ../web/src/lib/utils.ts `toDateTimeLocalValue`.
   */
  public static String toDateTimeLocalValue(String iso) {
    if (iso == null || iso.isBlank()) {
      return "";
    }
    try {
      return OffsetDateTime.parse(iso).atZoneSameInstant(ZoneId.systemDefault()).toLocalDateTime().format(DATETIME_LOCAL_INPUT);
    } catch (DateTimeParseException e) {
      return "";
    }
  }

  /**
   * The inverse of {@link #toDateTimeLocalValue}: converts the raw value an HTML
   * `<input type="datetime-local">` submits (local time, no timezone/seconds) into a full
   * ISO-8601 UTC instant string, matching the reference web app's `new Date(values.startsAt).
   * toISOString()` in its create/edit event handlers.
   */
  public static String parseDateTimeLocalToIso(String value) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException("Date and time is required");
    }
    try {
      LocalDateTime local = LocalDateTime.parse(value, DATETIME_LOCAL_INPUT);
      return local.atZone(ZoneId.systemDefault()).toInstant().toString();
    } catch (DateTimeParseException e) {
      throw new IllegalArgumentException("Enter a valid date and time", e);
    }
  }
}
