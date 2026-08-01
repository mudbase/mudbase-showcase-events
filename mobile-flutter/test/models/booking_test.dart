import 'package:mudbase_showcase_events/models/booking.dart';
import 'package:test/test.dart';

void main() {
  group('BookingStatus.fromWire / wireValue', () {
    test('round-trips every known wire value', () {
      const cases = {
        'confirmed': BookingStatus.confirmed,
        'waitlisted': BookingStatus.waitlisted,
        'cancelled': BookingStatus.cancelled,
        'checked_in': BookingStatus.checkedIn,
      };
      for (final entry in cases.entries) {
        expect(BookingStatus.fromWire(entry.key), entry.value);
        expect(entry.value.wireValue, entry.key);
      }
    });

    test('falls back to cancelled for an unrecognized wire value', () {
      expect(BookingStatus.fromWire('made_up_status'), BookingStatus.cancelled);
      expect(BookingStatus.fromWire(null), BookingStatus.cancelled);
    });

    test('has a human-readable label for every status', () {
      expect(BookingStatus.confirmed.label, 'Confirmed');
      expect(BookingStatus.waitlisted.label, 'Waitlisted');
      expect(BookingStatus.cancelled.label, 'Cancelled');
      expect(BookingStatus.checkedIn.label, 'Checked in');
    });
  });

  group('Booking.fromJson', () {
    test('parses a full document', () {
      final booking = Booking.fromJson({
        '_id': 'bk1',
        'eventId': 'evt1',
        'userId': 'user1',
        'userName': 'Ada Attendee',
        'status': 'confirmed',
        'qrToken': 'abc123',
        'createdAt': '2026-08-01T00:00:00.000Z',
      });

      expect(booking.id, 'bk1');
      expect(booking.eventId, 'evt1');
      expect(booking.userId, 'user1');
      expect(booking.userName, 'Ada Attendee');
      expect(booking.status, BookingStatus.confirmed);
      expect(booking.qrToken, 'abc123');
    });

    test('defaults missing fields safely', () {
      final booking = Booking.fromJson(const {});
      expect(booking.id, '');
      expect(booking.eventId, '');
      expect(booking.status, BookingStatus.cancelled);
      expect(booking.qrToken, '');
    });
  });
}
