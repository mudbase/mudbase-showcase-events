package dev.mudbase.showcase.events.service;

import dev.mudbase.showcase.events.config.MudbaseProperties;
import dev.mudbase.showcase.events.domain.BookingDoc;
import dev.mudbase.showcase.events.mudbase.MudbaseDataClient;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * Re-derives which bookings for an event should hold a confirmed seat versus sit on the waitlist,
 * and patches only the ones whose current status disagrees with that derivation. Ported from the
 * reference web app's `reconcileEventCapacity` (../web/src/lib/capacity.ts) - same algorithm,
 * same rationale, kept as its own component here (rather than folded into {@link
 * dev.mudbase.showcase.events.service.BookingService}) for the same separation-of-concerns reason
 * the reference keeps it in its own module.
 *
 * <p>Mudbase (a generic-CRUD BaaS) has no cross-document transactions or atomic counters, so a
 * plain "count confirmed, then create" is inherently racy: two simultaneous booking requests can
 * both read the same pre-write count and both decide "there's room". This narrows that race
 * window by re-deriving truth from a fresh read (creation-order priority: the first {@code
 * capacity} bookings, oldest first, among confirmed+waitlisted, are the ones entitled to a seat)
 * and correcting any booking that disagrees - whether that means demoting an overshoot back to
 * waitlisted, or promoting the earliest waitlisted booking once a cancellation frees a seat.
 *
 * <p>Deliberately excludes {@code checked_in} bookings from the capacity count (see
 * plan/build-plan.md "Capacity-Race Handling Approach") - capacity is defined in terms of {@code
 * confirmed} bookings specifically, and running this after check-in would incorrectly free an
 * already-seated attendee's slot for someone else on the waitlist.
 */
@Component
public class CapacityReconciler {

  // Generous ceiling on how many live (confirmed+waitlisted) bookings a single event can have for
  // reconciliation purposes - well beyond any capacity this demo app's form allows creating, so it
  // never truncates the real data.
  private static final int RECONCILE_FETCH_LIMIT = 1000;

  private final MudbaseDataClient dataClient;
  private final MudbaseProperties properties;
  private final ActivityService activityService;

  public CapacityReconciler(MudbaseDataClient dataClient, MudbaseProperties properties, ActivityService activityService) {
    this.dataClient = dataClient;
    this.properties = properties;
    this.activityService = activityService;
  }

  public void reconcile(String bearerToken, String eventId, int capacity) {
    List<BookingDoc> confirmed =
        dataClient
            .list(
                bearerToken,
                properties.getBookingsCollectionId(),
                Map.of("eventId", eventId, "status", BookingDoc.CONFIRMED),
                "createdAt",
                1,
                RECONCILE_FETCH_LIMIT)
            .stream()
            .map(BookingDoc::fromDocument)
            .toList();
    List<BookingDoc> waitlisted =
        dataClient
            .list(
                bearerToken,
                properties.getBookingsCollectionId(),
                Map.of("eventId", eventId, "status", BookingDoc.WAITLISTED),
                "createdAt",
                1,
                RECONCILE_FETCH_LIMIT)
            .stream()
            .map(BookingDoc::fromDocument)
            .toList();

    List<BookingDoc> live = new ArrayList<>(confirmed.size() + waitlisted.size());
    live.addAll(confirmed);
    live.addAll(waitlisted);
    live.sort(Comparator.comparing(CapacityReconciler::parseCreatedAt));

    for (int i = 0; i < live.size(); i++) {
      BookingDoc booking = live.get(i);
      boolean shouldBeConfirmed = i < capacity;

      if (shouldBeConfirmed && !BookingDoc.CONFIRMED.equals(booking.getStatus())) {
        dataClient.update(
            bearerToken, properties.getBookingsCollectionId(), booking.getId(), Map.of("status", BookingDoc.CONFIRMED));
        activityService.record(bearerToken, eventId, booking.getUserId(), booking.getUserName(), "booking_promoted");
      } else if (!shouldBeConfirmed && !BookingDoc.WAITLISTED.equals(booking.getStatus())) {
        dataClient.update(
            bearerToken, properties.getBookingsCollectionId(), booking.getId(), Map.of("status", BookingDoc.WAITLISTED));
        activityService.record(bearerToken, eventId, booking.getUserId(), booking.getUserName(), "booking_waitlisted");
      }
    }
  }

  private static Instant parseCreatedAt(BookingDoc booking) {
    try {
      return OffsetDateTime.parse(booking.getCreatedAt()).toInstant();
    } catch (RuntimeException e) {
      // No parseable createdAt (shouldn't happen against the real API) - treat as oldest so it
      // never jumps ahead of documents with a real timestamp.
      return Instant.EPOCH;
    }
  }
}
