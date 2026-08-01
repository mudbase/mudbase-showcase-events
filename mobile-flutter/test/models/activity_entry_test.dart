import 'package:mudbase_showcase_events/models/activity_entry.dart';
import 'package:test/test.dart';

void main() {
  group('ActivityAction.fromWire / wireValue', () {
    test('round-trips every known wire value', () {
      const cases = {
        'booking_confirmed': ActivityAction.bookingConfirmed,
        'booking_waitlisted': ActivityAction.bookingWaitlisted,
        'booking_cancelled': ActivityAction.bookingCancelled,
        'booking_promoted': ActivityAction.bookingPromoted,
        'checked_in': ActivityAction.checkedIn,
        'event_created': ActivityAction.eventCreated,
        'event_updated': ActivityAction.eventUpdated,
      };
      for (final entry in cases.entries) {
        expect(ActivityAction.fromWire(entry.key), entry.value);
        expect(entry.value.wireValue, entry.key);
      }
    });

    test('falls back to unknown for an unrecognized wire value', () {
      expect(
        ActivityAction.fromWire('some_future_action'),
        ActivityAction.unknown,
      );
      expect(ActivityAction.fromWire(null), ActivityAction.unknown);
    });
  });

  group('ActivityEntry.fromJson', () {
    test('parses a full document', () {
      final entry = ActivityEntry.fromJson({
        '_id': 'act1',
        'eventId': 'evt1',
        'actorId': 'user1',
        'actorName': 'Ada Attendee',
        'action': 'booking_confirmed',
        'createdAt': '2026-08-01T00:00:00.000Z',
      });

      expect(entry.id, 'act1');
      expect(entry.eventId, 'evt1');
      expect(entry.actorId, 'user1');
      expect(entry.actorName, 'Ada Attendee');
      expect(entry.action, ActivityAction.bookingConfirmed);
    });

    test('defaults missing fields safely', () {
      final entry = ActivityEntry.fromJson(const {});
      expect(entry.id, '');
      expect(entry.action, ActivityAction.unknown);
    });
  });
}
