import 'package:mudbase_showcase_events/core/capacity.dart';
import 'package:mudbase_showcase_events/models/booking.dart';
import 'package:test/test.dart';

Booking _booking(String id, BookingStatus status, DateTime createdAt) {
  return Booking(
    id: id,
    eventId: 'evt1',
    userId: 'user-$id',
    userName: 'User $id',
    status: status,
    qrToken: 'qr-$id',
    createdAt: createdAt,
  );
}

void main() {
  group('deriveReconciliationOrder', () {
    test('sorts confirmed+waitlisted bookings oldest first', () {
      final base = DateTime(2026, 1, 1);
      final third = _booking(
        '3',
        BookingStatus.waitlisted,
        base.add(const Duration(minutes: 3)),
      );
      final first = _booking(
        '1',
        BookingStatus.confirmed,
        base.add(const Duration(minutes: 1)),
      );
      final second = _booking(
        '2',
        BookingStatus.confirmed,
        base.add(const Duration(minutes: 2)),
      );

      final ordered = deriveReconciliationOrder([third, first, second]);

      expect(ordered.map((b) => b.id).toList(), ['1', '2', '3']);
    });

    test('does not mutate the input list', () {
      final base = DateTime(2026, 1, 1);
      final list = [
        _booking(
          '2',
          BookingStatus.confirmed,
          base.add(const Duration(minutes: 2)),
        ),
        _booking(
          '1',
          BookingStatus.confirmed,
          base.add(const Duration(minutes: 1)),
        ),
      ];
      final originalOrder = list.map((b) => b.id).toList();

      deriveReconciliationOrder(list);

      expect(list.map((b) => b.id).toList(), originalOrder);
    });

    test('an empty input produces an empty order', () {
      expect(deriveReconciliationOrder(const []), isEmpty);
    });
  });

  group('reconciliation decision rule (index < capacity)', () {
    // This mirrors the exact boundary `reconcileEventCapacity` applies to
    // the ordered list - the first `capacity` entries (oldest first) are
    // entitled to a confirmed seat, everything after is waitlisted. The
    // network-calling half of reconcileEventCapacity itself is exercised
    // live in tool/manual_test.dart (see plan/build-plan.md "Live Smoke
    // Test Results") since it requires real repository I/O.
    test(
      'the first N bookings (capacity N) are confirmed-eligible, the rest are not',
      () {
        final base = DateTime(2026, 1, 1);
        final bookings = List.generate(
          5,
          (i) => _booking(
            '$i',
            BookingStatus.confirmed,
            base.add(Duration(minutes: i)),
          ),
        );
        const capacity = 3;

        final ordered = deriveReconciliationOrder(bookings);
        final eligibility = [
          for (var i = 0; i < ordered.length; i++) i < capacity,
        ];

        expect(eligibility, [true, true, true, false, false]);
      },
    );

    test('reordering by creation time changes which bookings are eligible', () {
      final base = DateTime(2026, 1, 1);
      // "3" was actually created earliest despite being passed in last,
      // scrambled order - the race-condition scenario this algorithm exists
      // to correct.
      final scrambled = [
        _booking(
          '1',
          BookingStatus.confirmed,
          base.add(const Duration(minutes: 5)),
        ),
        _booking(
          '2',
          BookingStatus.confirmed,
          base.add(const Duration(minutes: 6)),
        ),
        _booking(
          '3',
          BookingStatus.confirmed,
          base.add(const Duration(minutes: 1)),
        ),
      ];
      const capacity = 2;

      final ordered = deriveReconciliationOrder(scrambled);
      final confirmedIds = [
        for (var i = 0; i < ordered.length; i++)
          if (i < capacity) ordered[i].id,
      ];

      expect(confirmedIds, ['3', '1']);
    });
  });
}
