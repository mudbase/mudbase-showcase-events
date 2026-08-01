import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capacity.dart';
import '../../core/formatters.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/repository_providers.dart';
import '../../models/activity_entry.dart';
import '../../models/booking.dart';
import '../../models/event.dart';
import '../auth/auth_controller.dart';

/// Everything one event detail screen needs as a single snapshot - mirrors
/// the reference web app's `/events/[id]` page, which independently reads
/// `useEvent`, `useConfirmedCount`, `useMyBookingForEvent`, and
/// `useEventActivity`. A Flutter screen needs one `AsyncValue` to build
/// against rather than four independent query hooks, same rationale the
/// sibling kanban port's `BoardController` documents for its own combined
/// state.
class EventDetailData {
  const EventDetailData({
    required this.event,
    required this.confirmedCount,
    required this.myActiveBooking,
    required this.activity,
  });

  final EventDoc event;
  final int confirmedCount;

  /// The signed-in user's own booking for this event that isn't cancelled,
  /// if any - mirrors the web app's `BookButton.tsx`
  /// (`existing?.data.find(b => b.status !== "cancelled")`), used to hide
  /// the Book button / show its status instead.
  final Booking? myActiveBooking;
  final List<ActivityEntry> activity;
}

enum CheckInOutcome {
  checkedIn,
  alreadyCheckedIn,
  cancelled,
  waitlisted,
  notFound,
}

class CheckInResult {
  const CheckInResult({required this.outcome, this.booking});

  final CheckInOutcome outcome;
  final Booking? booking;
}

/// Owns one event's full detail state + every booking/event mutation a
/// viewer of that event can perform - mirrors the reference web app's
/// `useEvent`/`useConfirmedCount`/`useMyBookingForEvent`/`useEventActivity`
/// plus `useCreateBooking`/`useCancelBooking`/`useCheckIn`/
/// `useUpdateEvent`/`useDeleteEvent` combined into one family notifier keyed
/// by `eventId`.
class EventDetailController
    extends FamilyAsyncNotifier<EventDetailData, String> {
  @override
  Future<EventDetailData> build(String arg) => _fetch(arg);

  Future<EventDetailData> _fetch(String eventId) async {
    final user = ref.read(authControllerProvider).valueOrNull;
    final authNotifier = ref.read(authControllerProvider.notifier);
    final eventRepo = ref.read(eventRepositoryProvider);
    final bookingRepo = ref.read(bookingRepositoryProvider);
    final activityRepo = ref.read(activityRepositoryProvider);

    return authNotifier.callAuthorized((token) async {
      final event = await eventRepo.getById(token: token, eventId: eventId);
      final confirmedCount = await bookingRepo.confirmedCount(
        token: token,
        eventId: eventId,
      );

      Booking? myActiveBooking;
      if (user != null) {
        final ownBookings = await bookingRepo.listForEventAndUser(
          token: token,
          eventId: eventId,
          userId: user.id,
        );
        for (final booking in ownBookings) {
          if (booking.status != BookingStatus.cancelled) {
            myActiveBooking = booking;
            break;
          }
        }
      }

      final activity = await activityRepo.listForEvent(
        token: token,
        eventId: eventId,
      );

      return EventDetailData(
        event: event,
        confirmedCount: confirmedCount,
        myActiveBooking: myActiveBooking,
        activity: activity,
      );
    });
  }

  /// Reloads without flashing a loading spinner over already-visible
  /// content - converts a failure into `AsyncError` (so `AsyncValueView`'s
  /// retry button appears) rather than swallowing it.
  Future<void> refresh() async {
    try {
      state = AsyncData(await _fetch(arg));
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// Books a spot using the capacity-race approach documented in
  /// `lib/core/capacity.dart`: decide the initial status from a fresh
  /// server-side confirmed count, write it, then run the shared
  /// reconciliation pass so a race against another concurrent booking
  /// self-corrects. Returns the booking's *post-reconciliation* status, not
  /// its tentative initial write, so the UI never reports a status that got
  /// corrected out from under it a moment later. Mirrors the web app's
  /// `useCreateBooking`.
  Future<BookingStatus> book() async {
    final data = state.valueOrNull;
    if (data == null) throw StateError('Event has not finished loading.');
    final user = ref.read(authControllerProvider).valueOrNull;
    if (user == null) throw StateError('Must be signed in to book.');

    final authNotifier = ref.read(authControllerProvider.notifier);
    final bookingRepo = ref.read(bookingRepositoryProvider);
    final activityRepo = ref.read(activityRepositoryProvider);
    final eventId = data.event.id;
    final capacity = data.event.capacity;

    final finalStatus = await authNotifier.callAuthorized((token) async {
      final confirmedCount = await bookingRepo.confirmedCount(
        token: token,
        eventId: eventId,
      );
      final initialStatus = confirmedCount < capacity
          ? BookingStatus.confirmed
          : BookingStatus.waitlisted;
      final qrToken = generateQrToken();

      final booking = await bookingRepo.create(
        token: token,
        eventId: eventId,
        userId: user.id,
        userName: user.fullName,
        status: initialStatus,
        qrToken: qrToken,
      );
      await activityRepo.log(
        token: token,
        eventId: eventId,
        actorId: user.id,
        actorName: user.fullName,
        action: initialStatus == BookingStatus.confirmed
            ? ActivityAction.bookingConfirmed
            : ActivityAction.bookingWaitlisted,
      );

      await reconcileEventCapacity(
        token: token,
        bookingRepository: bookingRepo,
        activityRepository: activityRepo,
        eventId: eventId,
        capacity: capacity,
      );

      // Re-read: reconciliation above may have demoted this exact booking
      // if it lost a race against another concurrent request that also
      // decided "confirmed" from the same pre-write count.
      final reconciled = await bookingRepo.getById(
        token: token,
        bookingId: booking.id,
      );
      return reconciled.status;
    });

    await refresh();
    return finalStatus;
  }

  /// Cancels the signed-in user's own active booking for this event, then
  /// reconciles so the earliest waitlisted booking is promoted into the
  /// freed seat. Mirrors the web app's `useCancelBooking`.
  Future<void> cancelMyBooking() async {
    final data = state.valueOrNull;
    final booking = data?.myActiveBooking;
    if (data == null || booking == null) {
      throw StateError('No active booking to cancel.');
    }
    final user = ref.read(authControllerProvider).valueOrNull;
    if (user == null) throw StateError('Must be signed in.');

    final authNotifier = ref.read(authControllerProvider.notifier);
    final bookingRepo = ref.read(bookingRepositoryProvider);
    final activityRepo = ref.read(activityRepositoryProvider);
    final eventId = data.event.id;
    final capacity = data.event.capacity;

    await authNotifier.callAuthorized((token) async {
      await bookingRepo.updateStatus(
        token: token,
        bookingId: booking.id,
        status: BookingStatus.cancelled,
      );
      await activityRepo.log(
        token: token,
        eventId: eventId,
        actorId: user.id,
        actorName: user.fullName,
        action: ActivityAction.bookingCancelled,
      );
      await reconcileEventCapacity(
        token: token,
        bookingRepository: bookingRepo,
        activityRepository: activityRepo,
        eventId: eventId,
        capacity: capacity,
      );
    });
    await refresh();
  }

  /// Organizer-only (own events; enforced server-side): looks up a booking
  /// by its scanned/pasted `qrToken` within this event and, if eligible,
  /// checks it in. Mirrors the web app's `useCheckIn` and
  /// `plan/build-plan.md` "Check-In Flow". Deliberately does *not* run
  /// capacity reconciliation afterward - see `lib/core/capacity.dart`.
  Future<CheckInResult> checkIn(String qrToken) async {
    final data = state.valueOrNull;
    if (data == null) throw StateError('Event has not finished loading.');
    final trimmed = qrToken.trim();
    if (trimmed.isEmpty)
      return const CheckInResult(outcome: CheckInOutcome.notFound);

    final eventId = data.event.id;
    final authNotifier = ref.read(authControllerProvider.notifier);
    final bookingRepo = ref.read(bookingRepositoryProvider);
    final activityRepo = ref.read(activityRepositoryProvider);

    final result = await authNotifier.callAuthorized((token) async {
      final booking = await bookingRepo.findByQrToken(
        token: token,
        eventId: eventId,
        qrToken: trimmed,
      );
      if (booking == null) {
        return const CheckInResult(outcome: CheckInOutcome.notFound);
      }
      return switch (booking.status) {
        BookingStatus.checkedIn => CheckInResult(
          outcome: CheckInOutcome.alreadyCheckedIn,
          booking: booking,
        ),
        BookingStatus.cancelled => CheckInResult(
          outcome: CheckInOutcome.cancelled,
          booking: booking,
        ),
        BookingStatus.waitlisted => CheckInResult(
          outcome: CheckInOutcome.waitlisted,
          booking: booking,
        ),
        BookingStatus.confirmed => await _completeCheckIn(
          token,
          bookingRepo,
          activityRepo,
          eventId,
          booking,
        ),
      };
    });

    if (result.outcome == CheckInOutcome.checkedIn) await refresh();
    return result;
  }

  Future<CheckInResult> _completeCheckIn(
    String token,
    BookingRepository bookingRepo,
    ActivityRepository activityRepo,
    String eventId,
    Booking booking,
  ) async {
    final updated = await bookingRepo.updateStatus(
      token: token,
      bookingId: booking.id,
      status: BookingStatus.checkedIn,
    );
    await activityRepo.log(
      token: token,
      eventId: eventId,
      actorId: booking.userId,
      actorName: booking.userName,
      action: ActivityAction.checkedIn,
    );
    return CheckInResult(outcome: CheckInOutcome.checkedIn, booking: updated);
  }

  /// Organizer-only (own events; enforced server-side): edits an event's
  /// details, then re-checks capacity against existing bookings (a capacity
  /// decrease can turn some previously-confirmed bookings into overshoots).
  /// Logs an `event_updated` activity row. Mirrors the web app's edit page.
  Future<void> updateEvent({
    required String title,
    String? description,
    required DateTime startsAt,
    required String location,
    required int capacity,
  }) async {
    final data = state.valueOrNull;
    if (data == null) throw StateError('Event has not finished loading.');
    final user = ref.read(authControllerProvider).valueOrNull;
    if (user == null) throw StateError('Must be signed in.');

    final authNotifier = ref.read(authControllerProvider.notifier);
    final eventRepo = ref.read(eventRepositoryProvider);
    final activityRepo = ref.read(activityRepositoryProvider);
    final bookingRepo = ref.read(bookingRepositoryProvider);
    final eventId = data.event.id;

    await authNotifier.callAuthorized((token) async {
      await eventRepo.update(
        token: token,
        eventId: eventId,
        title: title,
        description: description,
        startsAt: startsAt,
        location: location,
        capacity: capacity,
      );
      await activityRepo.log(
        token: token,
        eventId: eventId,
        actorId: user.id,
        actorName: user.fullName,
        action: ActivityAction.eventUpdated,
      );
      await reconcileEventCapacity(
        token: token,
        bookingRepository: bookingRepo,
        activityRepository: activityRepo,
        eventId: eventId,
        capacity: capacity,
      );
    });
    await refresh();
  }

  /// Organizer-only (own events; enforced server-side): deletes the event.
  /// The caller navigates away on success - there is nothing left for this
  /// controller to hold state for once the underlying document is gone.
  Future<void> deleteEvent() async {
    final data = state.valueOrNull;
    if (data == null) throw StateError('Event has not finished loading.');
    final authNotifier = ref.read(authControllerProvider.notifier);
    final eventRepo = ref.read(eventRepositoryProvider);
    await authNotifier.callAuthorized(
      (token) => eventRepo.delete(token: token, eventId: data.event.id),
    );
  }
}

final eventDetailControllerProvider =
    AsyncNotifierProvider.family<
      EventDetailController,
      EventDetailData,
      String
    >(EventDetailController.new);
