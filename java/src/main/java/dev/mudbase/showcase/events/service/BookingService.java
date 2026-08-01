package dev.mudbase.showcase.events.service;

import dev.mudbase.showcase.events.auth.AuthSession;
import dev.mudbase.showcase.events.config.MudbaseProperties;
import dev.mudbase.showcase.events.domain.BookingDoc;
import dev.mudbase.showcase.events.domain.EventDoc;
import dev.mudbase.showcase.events.mudbase.DocumentMapper;
import dev.mudbase.showcase.events.mudbase.MudbaseApiException;
import dev.mudbase.showcase.events.mudbase.MudbaseDataClient;
import dev.mudbase.showcase.events.support.ForbiddenActionException;
import dev.mudbase.showcase.events.support.QrTokenGenerator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.stereotype.Service;

/**
 * Reads and writes the `bookings` collection: creation with the capacity-race approach documented
 * in plan/build-plan.md (decide the initial status from a fresh server-side confirmed count,
 * write it, then run {@link CapacityReconciler} so a race against another concurrent booking
 * self-corrects), cancellation (which re-runs reconciliation so the earliest waitlisted booking
 * is promoted into the freed seat), and organizer QR-token check-in. Mirrors the reference web
 * app's `useCreateBooking`/`useCancelBooking`/`useCheckIn` (../web/src/hooks/useBookings.ts)
 * request-shape-for-request-shape.
 */
@Service
public class BookingService {

  private static final int MY_BOOKINGS_LIMIT = 100;
  private static final int EXISTING_BOOKING_LOOKUP_LIMIT = 20;

  /** Outcome of an organizer's QR-token check-in attempt - mirrors the reference web app's `CheckInOutcome`. */
  public enum CheckInOutcome {
    CHECKED_IN,
    ALREADY_CHECKED_IN,
    CANCELLED,
    WAITLISTED,
    NOT_FOUND
  }

  public record CheckInResult(CheckInOutcome outcome, BookingDoc booking) {
    public static CheckInResult of(CheckInOutcome outcome, BookingDoc booking) {
      return new CheckInResult(outcome, booking);
    }
  }

  private final MudbaseDataClient dataClient;
  private final MudbaseProperties properties;
  private final ActivityService activityService;
  private final CapacityReconciler capacityReconciler;
  private final EventService eventService;

  public BookingService(
      MudbaseDataClient dataClient,
      MudbaseProperties properties,
      ActivityService activityService,
      CapacityReconciler capacityReconciler,
      EventService eventService) {
    this.dataClient = dataClient;
    this.properties = properties;
    this.activityService = activityService;
    this.capacityReconciler = capacityReconciler;
    this.eventService = eventService;
  }

  /** The signed-in user's own bookings across every event, newest first. */
  public List<BookingDoc> myBookings(AuthSession actor) {
    return dataClient
        .list(actor.getToken(), properties.getBookingsCollectionId(), Map.of("userId", actor.getUserId()), "-createdAt", 1, MY_BOOKINGS_LIMIT)
        .stream()
        .map(BookingDoc::fromDocument)
        .toList();
  }

  /** The signed-in user's own non-cancelled booking for one event, if any - used to swap the Book button for a status badge. */
  public Optional<BookingDoc> myActiveBookingForEvent(AuthSession actor, String eventId) {
    return dataClient
        .list(
            actor.getToken(),
            properties.getBookingsCollectionId(),
            Map.of("eventId", eventId, "userId", actor.getUserId()),
            "-createdAt",
            1,
            EXISTING_BOOKING_LOOKUP_LIMIT)
        .stream()
        .map(BookingDoc::fromDocument)
        .filter(booking -> !booking.isCancelled())
        .findFirst();
  }

  /**
   * Creates a booking using the capacity-race approach documented in plan/build-plan.md: decide
   * the initial status from a fresh server-side confirmed count, write it, then run the shared
   * reconciliation pass so a race against another concurrent booking self-corrects. Returns the
   * booking's *post-reconciliation* state, not its tentative initial write, so the caller never
   * reports a status that got corrected out from under it a moment later.
   */
  public BookingDoc createBooking(AuthSession actor, EventDoc event) {
    if (event.isOwnedBy(actor.getUserId())) {
      throw new ForbiddenActionException("You can't book your own event.");
    }

    long confirmedCount =
        dataClient.count(
            actor.getToken(), properties.getBookingsCollectionId(), Map.of("eventId", event.getId(), "status", BookingDoc.CONFIRMED));
    String initialStatus = confirmedCount < event.getCapacity() ? BookingDoc.CONFIRMED : BookingDoc.WAITLISTED;
    String qrToken = QrTokenGenerator.generate();

    Map<String, Object> body = new LinkedHashMap<>();
    body.put("eventId", event.getId());
    body.put("userId", actor.getUserId());
    body.put("userName", actor.getDisplayName());
    body.put("status", initialStatus);
    body.put("qrToken", qrToken);

    Map<String, Object> created = dataClient.create(actor.getToken(), properties.getBookingsCollectionId(), body);
    String bookingId = DocumentMapper.getId(created);

    activityService.record(
        actor.getToken(),
        event.getId(),
        actor.getUserId(),
        actor.getDisplayName(),
        BookingDoc.CONFIRMED.equals(initialStatus) ? "booking_confirmed" : "booking_waitlisted");

    capacityReconciler.reconcile(actor.getToken(), event.getId(), event.getCapacity());

    // Re-read: reconciliation above may have demoted this exact booking if it lost a race
    // against another concurrent request that also decided "confirmed" from the same
    // pre-write count.
    return BookingDoc.fromDocument(dataClient.get(actor.getToken(), properties.getBookingsCollectionId(), bookingId));
  }

  /** Cancels the caller's own booking, then reconciles so the earliest waitlisted booking is promoted into the freed seat. */
  public void cancelBooking(AuthSession actor, String bookingId) {
    Map<String, Object> raw;
    try {
      raw = dataClient.get(actor.getToken(), properties.getBookingsCollectionId(), bookingId);
    } catch (MudbaseApiException e) {
      throw new ForbiddenActionException("This booking is no longer available.");
    }
    BookingDoc booking = BookingDoc.fromDocument(raw);
    if (!booking.isOwnedBy(actor.getUserId())) {
      throw new ForbiddenActionException("You can only cancel your own bookings.");
    }
    if (booking.isCancelled()) {
      return; // Already cancelled - idempotent no-op, matching the UI hiding the Cancel action.
    }

    dataClient.update(actor.getToken(), properties.getBookingsCollectionId(), bookingId, Map.of("status", BookingDoc.CANCELLED));
    activityService.record(actor.getToken(), booking.getEventId(), actor.getUserId(), actor.getDisplayName(), "booking_cancelled");

    EventDoc event = eventService.findById(actor.getToken(), booking.getEventId()).orElse(null);
    if (event != null) {
      capacityReconciler.reconcile(actor.getToken(), booking.getEventId(), event.getCapacity());
    }
  }

  /**
   * Looks up a booking by its scanned/pasted {@code qrToken} within one event and, if eligible,
   * checks it in. Organizer-only, and only for events the organizer themselves organizes -
   * enforced via {@link EventService#requireOwnedByOrganizer} before any lookup is attempted.
   */
  public CheckInResult checkIn(AuthSession organizer, EventDoc event, String rawQrToken) {
    eventService.requireOwnedByOrganizer(organizer, event, "check guests in for");

    String trimmed = rawQrToken == null ? "" : rawQrToken.trim();
    if (trimmed.isEmpty()) {
      return CheckInResult.of(CheckInOutcome.NOT_FOUND, null);
    }

    List<Map<String, Object>> matches =
        dataClient.list(
            organizer.getToken(), properties.getBookingsCollectionId(), Map.of("eventId", event.getId(), "qrToken", trimmed), null, 1, 1);
    if (matches.isEmpty()) {
      return CheckInResult.of(CheckInOutcome.NOT_FOUND, null);
    }

    BookingDoc booking = BookingDoc.fromDocument(matches.get(0));
    if (BookingDoc.CHECKED_IN.equals(booking.getStatus())) {
      return CheckInResult.of(CheckInOutcome.ALREADY_CHECKED_IN, booking);
    }
    if (booking.isCancelled()) {
      return CheckInResult.of(CheckInOutcome.CANCELLED, booking);
    }
    if (BookingDoc.WAITLISTED.equals(booking.getStatus())) {
      return CheckInResult.of(CheckInOutcome.WAITLISTED, booking);
    }

    Map<String, Object> updated =
        dataClient.update(organizer.getToken(), properties.getBookingsCollectionId(), booking.getId(), Map.of("status", BookingDoc.CHECKED_IN));
    activityService.record(organizer.getToken(), event.getId(), booking.getUserId(), booking.getUserName(), "checked_in");
    return CheckInResult.of(CheckInOutcome.CHECKED_IN, BookingDoc.fromDocument(updated));
  }
}
