import '../data/repositories/activity_repository.dart';
import '../data/repositories/booking_repository.dart';
import '../models/activity_entry.dart';
import '../models/booking.dart';

/// Re-derives which bookings for an event should hold a confirmed seat
/// versus sit on the waitlist, and patches only the ones whose current
/// status disagrees with that derivation. Ports `reconcileEventCapacity` in
/// the reference web app's `src/lib/capacity.ts` verbatim - see that file
/// for the full rationale; the summary:
///
/// Mudbase (a generic-CRUD BaaS) has no cross-document transactions or
/// atomic counters, so a plain "count confirmed, then create" is inherently
/// racy: two simultaneous booking requests can both read the same pre-write
/// count and both decide "there's room". This function narrows that race
/// window by re-deriving truth from a fresh read (creation-order priority:
/// the first `capacity` bookings, oldest first, among confirmed+waitlisted,
/// are the ones entitled to a seat) and correcting any booking that
/// disagrees - whether that means demoting an overshoot back to waitlisted,
/// or promoting the earliest waitlisted booking once a cancellation frees a
/// seat.
///
/// Deliberately excludes `checkedIn` bookings from the capacity count (see
/// `plan/build-plan.md` "Capacity-Race Handling Approach") - the task's spec
/// defines capacity in terms of confirmed bookings specifically, and running
/// this after check-in would incorrectly free an already-seated attendee's
/// slot for someone else.
Future<void> reconcileEventCapacity({
  required String token,
  required BookingRepository bookingRepository,
  required ActivityRepository activityRepository,
  required String eventId,
  required int capacity,
}) async {
  final results = await Future.wait([
    bookingRepository.listForEvent(
      token: token,
      eventId: eventId,
      status: 'confirmed',
      sort: 'createdAt',
      limit: BookingRepository.reconcileFetchLimit,
    ),
    bookingRepository.listForEvent(
      token: token,
      eventId: eventId,
      status: 'waitlisted',
      sort: 'createdAt',
      limit: BookingRepository.reconcileFetchLimit,
    ),
  ]);

  final live = deriveReconciliationOrder([...results[0], ...results[1]]);

  final corrections = <Future<void>>[];
  for (var index = 0; index < live.length; index++) {
    final booking = live[index];
    final shouldBeConfirmed = index < capacity;

    if (shouldBeConfirmed && booking.status != BookingStatus.confirmed) {
      corrections.add(
        _promote(
          token,
          bookingRepository,
          activityRepository,
          eventId,
          booking,
        ),
      );
    } else if (!shouldBeConfirmed &&
        booking.status != BookingStatus.waitlisted) {
      corrections.add(
        _demote(token, bookingRepository, activityRepository, eventId, booking),
      );
    }
  }

  await Future.wait(corrections);
}

/// The pure derivation half of reconciliation, split out from the I/O above
/// specifically so it is unit-testable with plain `dart test` and no network
/// dependency: sorts confirmed+waitlisted bookings by creation order
/// (oldest first), which is the priority order reconciliation applies.
List<Booking> deriveReconciliationOrder(List<Booking> confirmedAndWaitlisted) {
  final sorted = [...confirmedAndWaitlisted]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return sorted;
}

Future<void> _promote(
  String token,
  BookingRepository bookingRepository,
  ActivityRepository activityRepository,
  String eventId,
  Booking booking,
) async {
  await bookingRepository.updateStatus(
    token: token,
    bookingId: booking.id,
    status: BookingStatus.confirmed,
  );
  await activityRepository.log(
    token: token,
    eventId: eventId,
    actorId: booking.userId,
    actorName: booking.userName,
    action: ActivityAction.bookingPromoted,
  );
}

Future<void> _demote(
  String token,
  BookingRepository bookingRepository,
  ActivityRepository activityRepository,
  String eventId,
  Booking booking,
) async {
  await bookingRepository.updateStatus(
    token: token,
    bookingId: booking.id,
    status: BookingStatus.waitlisted,
  );
  await activityRepository.log(
    token: token,
    eventId: eventId,
    actorId: booking.userId,
    actorName: booking.userName,
    action: ActivityAction.bookingWaitlisted,
  );
}
