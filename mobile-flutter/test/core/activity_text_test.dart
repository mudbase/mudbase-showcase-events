import 'package:mudbase_showcase_events/core/activity_text.dart';
import 'package:mudbase_showcase_events/models/activity_entry.dart';
import 'package:test/test.dart';

ActivityEntry _entry(
  ActivityAction action, {
  String actorName = 'Ada Attendee',
}) {
  return ActivityEntry(
    id: 'act1',
    eventId: 'evt1',
    actorId: 'user1',
    actorName: actorName,
    action: action,
    createdAt: DateTime.now(),
  );
}

void main() {
  group('describeActivity', () {
    test('describes every known action', () {
      expect(
        describeActivity(_entry(ActivityAction.bookingConfirmed)),
        'Ada Attendee booked (confirmed)',
      );
      expect(
        describeActivity(_entry(ActivityAction.bookingWaitlisted)),
        'Ada Attendee joined the waitlist',
      );
      expect(
        describeActivity(_entry(ActivityAction.bookingCancelled)),
        'Ada Attendee cancelled their booking',
      );
      expect(
        describeActivity(_entry(ActivityAction.bookingPromoted)),
        'Ada Attendee was promoted from the waitlist',
      );
      expect(
        describeActivity(_entry(ActivityAction.checkedIn)),
        'Ada Attendee checked in',
      );
      expect(
        describeActivity(_entry(ActivityAction.eventCreated)),
        'Ada Attendee created this event',
      );
      expect(
        describeActivity(_entry(ActivityAction.eventUpdated)),
        'Ada Attendee updated this event',
      );
    });

    test('falls back gracefully for the unknown action', () {
      expect(
        describeActivity(_entry(ActivityAction.unknown)),
        'Ada Attendee did something on this event',
      );
    });

    test('substitutes "Someone" when actorName is empty', () {
      expect(
        describeActivity(_entry(ActivityAction.checkedIn, actorName: '')),
        'Someone checked in',
      );
    });
  });
}
