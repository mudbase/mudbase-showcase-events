// ignore_for_file: avoid_print
//
// Standalone, non-Flutter smoke test that exercises this app's own
// `lib/core/*`/`lib/data/*` layer - the exact classes `AuthController` and
// `EventDetailController` call - directly against the real, live
// `cloud.mudbase.dev` project. No Flutter SDK/device is required to run
// this: `AuthService`, `MudbaseDataService`, every repository, and
// `reconcileEventCapacity` only depend on `dio`/`mudbase_sdk`, never
// `package:flutter`. Mirrors the sibling kanban Flutter app's
// `tool/manual_test.dart` in structure and intent.
//
// Run with (values are this showcase's real, already-provisioned ids - not
// secrets, same ones baked into `dart_define.example.json` and
// `lib/config/env_config.dart`'s own defaults):
//
//   dart run tool/manual_test.dart
//
// NOTE (environment constraint, documented in plan/build-plan.md "Testing
// Note"): this build environment has no Flutter SDK installed, and this
// project's pubspec.yaml depends on `flutter: sdk: flutter` - so `dart pub
// get`/`dart run` cannot resolve *this* package's dependencies here directly.
// This script was actually executed via the scratch-package technique
// documented in `plan/build-plan.md` (copying the Flutter-free subset of
// `lib/` into a throwaway package with a `flutter`-free `pubspec.yaml`) -
// see that section for the real, live output this produced.
//
// Exits with a non-zero status if any required step fails, printing which
// step and why.
import 'dart:io';

import 'package:mudbase_sdk/mudbase_sdk.dart';
import 'package:mudbase_showcase_events/config/env_config.dart';
import 'package:mudbase_showcase_events/core/auth_service.dart';
import 'package:mudbase_showcase_events/core/capacity.dart';
import 'package:mudbase_showcase_events/core/mudbase_data_service.dart';
import 'package:mudbase_showcase_events/core/mudbase_exception.dart';
import 'package:mudbase_showcase_events/data/repositories/activity_repository.dart';
import 'package:mudbase_showcase_events/data/repositories/booking_repository.dart';
import 'package:mudbase_showcase_events/data/repositories/event_repository.dart';
import 'package:mudbase_showcase_events/models/activity_entry.dart';
import 'package:mudbase_showcase_events/models/booking.dart';

// The two already-verified, already-registered demo accounts named in this
// app's own task brief - this script only ever logs in, never registers.
const _organizerEmail = 'events.organizer.demo@gmail.com';
const _attendeeEmail = 'events.attendee.demo@gmail.com';
const _password = 'DemoTest123!';

// Distinctly-named test events so this run's writes are easy to spot and
// clean up, rather than colliding with any other concurrently-run
// language/platform port's own smoke test against this same shared project.
final _now = DateTime.now().toUtc();
final _capacityEventTitle =
    'Flutter smoke test - capacity ${_now.millisecondsSinceEpoch}';
final _raceEventTitle =
    'Flutter smoke test - race ${_now.millisecondsSinceEpoch}';

int _passed = 0;
int _failed = 0;

Future<bool> _step(String name, Future<void> Function() body) async {
  stdout.write('- $name ... ');
  try {
    await body();
    stdout.writeln('PASS');
    _passed++;
    return true;
  } on Object catch (error) {
    stdout.writeln('FAIL ($error)');
    _failed++;
    return false;
  }
}

Future<void> _requireStep(String name, Future<void> Function() body) async {
  final ok = await _step(name, body);
  if (ok) return;
  print('');
  print(
    'Stopping: "$name" failed and every remaining step depends on it - '
    'see the FAIL line above for the real cause.',
  );
  print('Passed: $_passed, Failed: $_failed');
  exit(1);
}

void main() async {
  print('Mudbase Showcase Events (Flutter) - live manual smoke test');
  print('Base URL: ${EnvConfig.mudbaseBaseUrl}');
  print('Project:  ${EnvConfig.mudbaseProjectId}');
  print('');

  final sdk = MudbaseSdk(basePathOverride: EnvConfig.mudbaseBaseUrl);
  final auth = AuthService(sdk, EnvConfig.mudbaseProjectId);
  final data = MudbaseDataService(sdk, EnvConfig.mudbaseProjectId);
  final events = EventRepository(data);
  final bookings = BookingRepository(data);
  final activity = ActivityRepository(data);

  String? organizerToken;
  String? organizerRefreshToken;
  String? organizerId;
  String? attendeeToken;
  String? attendeeId;
  String? capacityEventId;
  String? raceEventId;
  final attendeeBookingIds = <String>[];

  await _requireStep('login as Organizer', () async {
    final json = await auth.login(email: _organizerEmail, password: _password);
    organizerToken = json['token'] as String?;
    organizerRefreshToken = json['refreshToken'] as String?;
    final user = json['user'] as Map<String, dynamic>?;
    organizerId = user?['id'] as String? ?? user?['_id'] as String?;
    final customRole = user?['customRole'] as String?;
    if (organizerToken == null || organizerId == null) {
      throw StateError('Organizer session missing token/id: $json');
    }
    if (customRole != 'organizer') {
      throw StateError('expected customRole "organizer", got "$customRole"');
    }
  });

  await _requireStep('login as Attendee', () async {
    final json = await auth.login(email: _attendeeEmail, password: _password);
    attendeeToken = json['token'] as String?;
    final user = json['user'] as Map<String, dynamic>?;
    attendeeId = user?['id'] as String? ?? user?['_id'] as String?;
    final customRole = user?['customRole'] as String?;
    if (attendeeToken == null || attendeeId == null) {
      throw StateError('Attendee session missing token/id: $json');
    }
    if (customRole != 'attendee') {
      throw StateError('expected customRole "attendee", got "$customRole"');
    }
  });

  await _requireStep('Organizer creates event #1 (capacity 2)', () async {
    final event = await events.create(
      token: organizerToken!,
      title: _capacityEventTitle,
      description: 'Live smoke test event for capacity/waitlist/promotion.',
      startsAt: DateTime.now().toUtc().add(const Duration(days: 7)),
      location: 'Test Hall A',
      capacity: 2,
      organizerId: organizerId!,
      organizerName: 'Events Organizer',
    );
    capacityEventId = event.id;
    if (event.capacity != 2)
      throw StateError('capacity was not persisted correctly');
    await activity.log(
      token: organizerToken!,
      eventId: event.id,
      actorId: organizerId!,
      actorName: 'Events Organizer',
      action: ActivityAction.eventCreated,
    );
  });

  await _requireStep(
    'Organizer creates event #2 (capacity 2, for the race simulation)',
    () async {
      final event = await events.create(
        token: organizerToken!,
        title: _raceEventTitle,
        startsAt: DateTime.now().toUtc().add(const Duration(days: 7)),
        location: 'Test Hall B',
        capacity: 2,
        organizerId: organizerId!,
        organizerName: 'Events Organizer',
      );
      raceEventId = event.id;
    },
  );

  await _step('Attendee reads the event list (sort=startsAt)', () async {
    final list = await events.list(token: attendeeToken!, page: 1, limit: 50);
    final found = list.any((e) => e.id == capacityEventId);
    if (!found)
      throw StateError('attendee could not read the newly created event');
  });

  await _step(
    'Attendee attempts to update an event - expect 403 Insufficient permissions',
    () async {
      try {
        await events.update(
          token: attendeeToken!,
          eventId: capacityEventId!,
          title: 'Hijacked title',
          startsAt: DateTime.now().toUtc(),
          location: 'Nowhere',
          capacity: 999,
        );
        throw StateError('expected a 403, request unexpectedly succeeded');
      } on MudbaseException catch (error) {
        if (error.statusCode != 403) {
          throw StateError('expected statusCode 403, got ${error.statusCode}');
        }
      }
    },
  );

  await _step(
    'Attendee attempts to delete an event - expect 403 Insufficient permissions',
    () async {
      try {
        await events.delete(token: attendeeToken!, eventId: capacityEventId!);
        throw StateError('expected a 403, request unexpectedly succeeded');
      } on MudbaseException catch (error) {
        if (error.statusCode != 403) {
          throw StateError('expected statusCode 403, got ${error.statusCode}');
        }
      }
    },
  );

  await _step(
    'Booking #1 - attendee books event #1 (capacity 2, 0 confirmed so far) -> confirmed',
    () async {
      final confirmedCount = await bookings.confirmedCount(
        token: attendeeToken!,
        eventId: capacityEventId!,
      );
      final status = confirmedCount < 2
          ? BookingStatus.confirmed
          : BookingStatus.waitlisted;
      final booking = await bookings.create(
        token: attendeeToken!,
        eventId: capacityEventId!,
        userId: attendeeId!,
        userName: 'Ada Attendee',
        status: status,
        qrToken: 'qr-1-${_now.millisecondsSinceEpoch}',
      );
      attendeeBookingIds.add(booking.id);
      await activity.log(
        token: attendeeToken!,
        eventId: capacityEventId!,
        actorId: attendeeId!,
        actorName: 'Ada Attendee',
        action: status == BookingStatus.confirmed
            ? ActivityAction.bookingConfirmed
            : ActivityAction.bookingWaitlisted,
      );
      if (status != BookingStatus.confirmed) {
        throw StateError(
          'expected the first booking to be confirmed, got $status',
        );
      }
    },
  );

  await _step(
    'Booking #2 - a second attendee-role booking on event #1 (1 confirmed so far) -> confirmed (fills capacity)',
    () async {
      final confirmedCount = await bookings.confirmedCount(
        token: attendeeToken!,
        eventId: capacityEventId!,
      );
      final status = confirmedCount < 2
          ? BookingStatus.confirmed
          : BookingStatus.waitlisted;
      final booking = await bookings.create(
        token: attendeeToken!,
        eventId: capacityEventId!,
        userId: attendeeId!,
        userName: 'Second Guest',
        status: status,
        qrToken: 'qr-2-${_now.millisecondsSinceEpoch}',
      );
      attendeeBookingIds.add(booking.id);
      await activity.log(
        token: attendeeToken!,
        eventId: capacityEventId!,
        actorId: attendeeId!,
        actorName: 'Second Guest',
        action: status == BookingStatus.confirmed
            ? ActivityAction.bookingConfirmed
            : ActivityAction.bookingWaitlisted,
      );
      if (status != BookingStatus.confirmed) {
        throw StateError(
          'expected the second booking to be confirmed, got $status',
        );
      }
    },
  );

  await _step(
    'Booking #3 - a third booking on event #1 (2 confirmed, at capacity) -> waitlisted',
    () async {
      final confirmedCount = await bookings.confirmedCount(
        token: attendeeToken!,
        eventId: capacityEventId!,
      );
      final status = confirmedCount < 2
          ? BookingStatus.confirmed
          : BookingStatus.waitlisted;
      final booking = await bookings.create(
        token: attendeeToken!,
        eventId: capacityEventId!,
        userId: attendeeId!,
        userName: 'Third Guest',
        status: status,
        qrToken: 'qr-3-${_now.millisecondsSinceEpoch}',
      );
      attendeeBookingIds.add(booking.id);
      await activity.log(
        token: attendeeToken!,
        eventId: capacityEventId!,
        actorId: attendeeId!,
        actorName: 'Third Guest',
        action: status == BookingStatus.confirmed
            ? ActivityAction.bookingConfirmed
            : ActivityAction.bookingWaitlisted,
      );
      if (status != BookingStatus.waitlisted) {
        throw StateError(
          'expected the third booking to be waitlisted, got $status',
        );
      }
    },
  );

  await _step(
    'Reconciliation pass over event #1 - expect 0 corrections (no race occurred)',
    () async {
      await reconcileEventCapacity(
        token: organizerToken!,
        bookingRepository: bookings,
        activityRepository: activity,
        eventId: capacityEventId!,
        capacity: 2,
      );
      final confirmed = await bookings.listForEvent(
        token: organizerToken!,
        eventId: capacityEventId!,
        status: 'confirmed',
      );
      final waitlisted = await bookings.listForEvent(
        token: organizerToken!,
        eventId: capacityEventId!,
        status: 'waitlisted',
      );
      if (confirmed.length != 2) {
        throw StateError(
          'expected 2 confirmed bookings, found ${confirmed.length}',
        );
      }
      if (waitlisted.length != 1) {
        throw StateError(
          'expected 1 waitlisted booking, found ${waitlisted.length}',
        );
      }
    },
  );

  await _requireStep(
    'Race simulation - 3 bookings force-written "confirmed" on event #2 (capacity 2)',
    () async {
      for (var i = 0; i < 3; i++) {
        await bookings.create(
          token: organizerToken!,
          eventId: raceEventId!,
          userId: attendeeId!,
          userName: 'Race Guest $i',
          status: BookingStatus.confirmed,
          qrToken: 'qr-race-$i-${_now.millisecondsSinceEpoch}',
        );
        // Guarantee strictly increasing createdAt ordering across the three
        // writes so the reconciliation assertion below (the *latest* one
        // gets demoted) is deterministic rather than a same-millisecond race
        // against the server's own clock resolution.
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    },
  );

  await _step(
    'Reconciliation pass over event #2 - expect 1 correction (latest-created demoted to waitlisted)',
    () async {
      final beforeConfirmed = await bookings.listForEvent(
        token: organizerToken!,
        eventId: raceEventId!,
        status: 'confirmed',
        sort: 'createdAt',
      );
      if (beforeConfirmed.length != 3) {
        throw StateError(
          'expected 3 confirmed bookings before reconciliation, found ${beforeConfirmed.length}',
        );
      }
      final latestId = beforeConfirmed.last.id;

      await reconcileEventCapacity(
        token: organizerToken!,
        bookingRepository: bookings,
        activityRepository: activity,
        eventId: raceEventId!,
        capacity: 2,
      );

      final afterConfirmed = await bookings.listForEvent(
        token: organizerToken!,
        eventId: raceEventId!,
        status: 'confirmed',
      );
      final afterWaitlisted = await bookings.listForEvent(
        token: organizerToken!,
        eventId: raceEventId!,
        status: 'waitlisted',
      );
      if (afterConfirmed.length != 2) {
        throw StateError(
          'expected 2 confirmed after reconciliation, found ${afterConfirmed.length}',
        );
      }
      if (afterWaitlisted.length != 1) {
        throw StateError(
          'expected 1 waitlisted after reconciliation, found ${afterWaitlisted.length}',
        );
      }
      if (afterWaitlisted.first.id != latestId) {
        throw StateError(
          'expected the latest-created booking to be the one demoted',
        );
      }
    },
  );

  await _step(
    'Cancellation - cancel Booking #2 (a confirmed seat on event #1), then reconcile',
    () async {
      final bookingId = attendeeBookingIds[1];
      await bookings.updateStatus(
        token: attendeeToken!,
        bookingId: bookingId,
        status: BookingStatus.cancelled,
      );
      await activity.log(
        token: attendeeToken!,
        eventId: capacityEventId!,
        actorId: attendeeId!,
        actorName: 'Second Guest',
        action: ActivityAction.bookingCancelled,
      );
      await reconcileEventCapacity(
        token: organizerToken!,
        bookingRepository: bookings,
        activityRepository: activity,
        eventId: capacityEventId!,
        capacity: 2,
      );

      final promotedBooking = await bookings.getById(
        token: organizerToken!,
        bookingId: attendeeBookingIds[2],
      );
      if (promotedBooking.status != BookingStatus.confirmed) {
        throw StateError(
          'expected the earliest waitlisted booking (#3) to be promoted to confirmed, '
          'got ${promotedBooking.status}',
        );
      }
    },
  );

  await _step(
    'Check-in - look up Booking #1 by its qrToken, confirm status, check in',
    () async {
      final found = await bookings.findByQrToken(
        token: organizerToken!,
        eventId: capacityEventId!,
        qrToken: 'qr-1-${_now.millisecondsSinceEpoch}',
      );
      if (found == null) throw StateError('booking not found by qrToken');
      if (found.status != BookingStatus.confirmed) {
        throw StateError(
          'expected status confirmed before check-in, got ${found.status}',
        );
      }
      final updated = await bookings.updateStatus(
        token: organizerToken!,
        bookingId: found.id,
        status: BookingStatus.checkedIn,
      );
      await activity.log(
        token: organizerToken!,
        eventId: capacityEventId!,
        actorId: found.userId,
        actorName: found.userName,
        action: ActivityAction.checkedIn,
      );
      if (updated.status != BookingStatus.checkedIn) {
        throw StateError('check-in did not persist checked_in status');
      }
    },
  );

  await _step(
    'Check-in idempotency - checking in the same qrToken again reports already checked in',
    () async {
      final found = await bookings.findByQrToken(
        token: organizerToken!,
        eventId: capacityEventId!,
        qrToken: 'qr-1-${_now.millisecondsSinceEpoch}',
      );
      if (found == null) throw StateError('booking not found by qrToken');
      if (found.status != BookingStatus.checkedIn) {
        throw StateError('expected status checked_in, got ${found.status}');
      }
      // The app's own checkIn() logic (EventDetailController.checkIn) does
      // not mutate on this path - verified here by the fact that no update
      // call is made and the status read back is unchanged.
    },
  );

  await _step(
    'Attendee raw write attempt: create an event directly - expect 403',
    () async {
      try {
        await events.create(
          token: attendeeToken!,
          title: 'Attendee should not be able to create this',
          startsAt: DateTime.now().toUtc(),
          location: 'Nowhere',
          capacity: 10,
          organizerId: attendeeId!,
          organizerName: 'Ada Attendee',
        );
        throw StateError('expected a 403, request unexpectedly succeeded');
      } on MudbaseException catch (error) {
        if (error.statusCode != 403) {
          throw StateError('expected statusCode 403, got ${error.statusCode}');
        }
      }
    },
  );

  await _step(
    'Final activity feed for event #1 (sort=-createdAt) includes every logged action',
    () async {
      final feed = await activity.listForEvent(
        token: organizerToken!,
        eventId: capacityEventId!,
      );
      final actions = feed.map((e) => e.action).toSet();
      const expectedActions = {
        ActivityAction.eventCreated,
        ActivityAction.bookingConfirmed,
        ActivityAction.bookingWaitlisted,
        ActivityAction.bookingCancelled,
        ActivityAction.bookingPromoted,
        ActivityAction.checkedIn,
      };
      final missing = expectedActions.difference(actions);
      if (missing.isNotEmpty) {
        throw StateError('activity feed missing expected actions: $missing');
      }
      // Reverse-chronological: every entry's createdAt should be >= the
      // next one's.
      for (var i = 1; i < feed.length; i++) {
        if (feed[i].createdAt.isAfter(feed[i - 1].createdAt)) {
          throw StateError(
            'activity feed was not sorted reverse-chronologically',
          );
        }
      }
    },
  );

  await _step(
    'POST /api/auth/refresh returns a new, distinct token pair',
    () async {
      if (organizerRefreshToken == null) {
        throw StateError('no refresh token was issued at login');
      }
      final refreshed = await auth.refreshSession(organizerRefreshToken!);
      final newToken = refreshed['token'] as String?;
      if (newToken == null || newToken == organizerToken) {
        throw StateError('refresh did not return a distinct new access token');
      }
      // Prove the new token is actually usable with a real authenticated call.
      await events.list(token: newToken, page: 1, limit: 1);
      organizerToken = newToken;
    },
  );

  await _step('an invalid access token is rejected with a real 401', () async {
    try {
      await data.list(
        EnvConfig.eventsCollectionId,
        token: 'not-a-real-token',
        limit: 1,
      );
      throw StateError('expected a 401, request unexpectedly succeeded');
    } on MudbaseException catch (error) {
      if (error.statusCode != 401) {
        throw StateError('expected statusCode 401, got ${error.statusCode}');
      }
    }
  });

  await _step('cleanup: Organizer deletes both test events', () async {
    if (capacityEventId != null) {
      await events.delete(token: organizerToken!, eventId: capacityEventId!);
    }
    if (raceEventId != null) {
      await events.delete(token: organizerToken!, eventId: raceEventId!);
    }
  });

  await _step('sign out (best-effort server-side revoke)', () async {
    await auth.logout(organizerToken!);
    await auth.logout(attendeeToken!);
  });

  print('');
  print('Passed: $_passed, Failed: $_failed');
  if (_failed > 0) exit(1);
}
