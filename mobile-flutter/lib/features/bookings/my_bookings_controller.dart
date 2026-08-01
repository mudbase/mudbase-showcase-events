import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capacity.dart';
import '../../core/mudbase_exception.dart';
import '../../data/repository_providers.dart';
import '../../models/activity_entry.dart';
import '../../models/booking.dart';
import '../../models/event.dart';
import '../auth/auth_controller.dart';

/// A booking joined against its event doc - there is no native join in a
/// generic-CRUD BaaS, so this app resolves each booking's `eventId` to a
/// full event record client-side, mirroring the reference web app's
/// `useEventsByIds` (used on its own `/bookings` page for the same reason).
/// [event] is `null` when the underlying event was deleted after the
/// booking was made - the UI shows a graceful fallback rather than crashing.
class BookingWithEvent {
  const BookingWithEvent({required this.booking, required this.event});

  final Booking booking;
  final EventDoc? event;
}

/// Owns the signed-in attendee's own bookings across every event, each
/// joined against its event - mirrors the web app's `/bookings` page
/// (`useMyBookings` + `useEventsByIds`) plus `useCancelBooking`.
class MyBookingsController extends AsyncNotifier<List<BookingWithEvent>> {
  @override
  Future<List<BookingWithEvent>> build() => _fetch();

  Future<List<BookingWithEvent>> _fetch() async {
    final user = ref.read(authControllerProvider).valueOrNull;
    if (user == null) return const [];

    final authNotifier = ref.read(authControllerProvider.notifier);
    final bookingRepo = ref.read(bookingRepositoryProvider);
    final eventRepo = ref.read(eventRepositoryProvider);

    return authNotifier.callAuthorized((token) async {
      final bookings = await bookingRepo.listForUser(
        token: token,
        userId: user.id,
      );
      return Future.wait(
        bookings.map((booking) async {
          EventDoc? event;
          try {
            event = await eventRepo.getById(
              token: token,
              eventId: booking.eventId,
            );
          } on MudbaseException {
            event = null;
          }
          return BookingWithEvent(booking: booking, event: event);
        }),
      );
    });
  }

  Future<void> refresh() async {
    try {
      state = AsyncData(await _fetch());
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// Cancels one of the signed-in user's own bookings, then reconciles that
  /// event's capacity so the earliest waitlisted booking is promoted into
  /// the freed seat. Requires the joined [item.event] (to know the
  /// capacity to reconcile against) - if the event was deleted, there is no
  /// capacity to reconcile, so this just cancels the booking itself.
  Future<void> cancelBooking(BookingWithEvent item) async {
    final user = ref.read(authControllerProvider).valueOrNull;
    if (user == null) throw StateError('Must be signed in.');

    final authNotifier = ref.read(authControllerProvider.notifier);
    final bookingRepo = ref.read(bookingRepositoryProvider);
    final activityRepo = ref.read(activityRepositoryProvider);
    final event = item.event;

    await authNotifier.callAuthorized((token) async {
      await bookingRepo.updateStatus(
        token: token,
        bookingId: item.booking.id,
        status: BookingStatus.cancelled,
      );
      await activityRepo.log(
        token: token,
        eventId: item.booking.eventId,
        actorId: user.id,
        actorName: user.fullName,
        action: ActivityAction.bookingCancelled,
      );
      if (event != null) {
        await reconcileEventCapacity(
          token: token,
          bookingRepository: bookingRepo,
          activityRepository: activityRepo,
          eventId: event.id,
          capacity: event.capacity,
        );
      }
    });
    await refresh();
  }
}

final myBookingsControllerProvider =
    AsyncNotifierProvider<MyBookingsController, List<BookingWithEvent>>(
      MyBookingsController.new,
    );
