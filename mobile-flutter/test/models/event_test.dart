import 'package:mudbase_showcase_events/models/event.dart';
import 'package:test/test.dart';

void main() {
  group('EventDoc.fromJson', () {
    test('parses a full document', () {
      final event = EventDoc.fromJson({
        '_id': 'evt1',
        'title': 'Launch Party',
        'description': 'Kickoff event',
        'startsAt': '2026-09-01T18:00:00.000Z',
        'location': 'Main Hall',
        'capacity': 50,
        'organizerId': 'org1',
        'organizerName': 'Ola Organizer',
        'createdAt': '2026-08-01T00:00:00.000Z',
      });

      expect(event.id, 'evt1');
      expect(event.title, 'Launch Party');
      expect(event.description, 'Kickoff event');
      expect(event.location, 'Main Hall');
      expect(event.capacity, 50);
      expect(event.organizerId, 'org1');
      expect(event.organizerName, 'Ola Organizer');
      expect(event.startsAt.toUtc().hour, 18);
    });

    test('defaults description to null when absent', () {
      final event = EventDoc.fromJson({
        '_id': 'evt2',
        'title': 'No description event',
        'startsAt': '2026-09-01T18:00:00.000Z',
        'location': 'Hall',
        'capacity': 10,
        'organizerId': 'org1',
        'organizerName': 'Org',
      });
      expect(event.description, isNull);
    });

    test('defaults missing numeric/string fields safely', () {
      final event = EventDoc.fromJson(const {});
      expect(event.id, '');
      expect(event.title, '');
      expect(event.capacity, 0);
      expect(event.location, '');
    });
  });

  group('EventDoc.isOrganizedBy', () {
    test('returns true when the given user id matches organizerId', () {
      final event = EventDoc.fromJson({
        '_id': 'evt1',
        'title': 'T',
        'startsAt': '2026-09-01T18:00:00.000Z',
        'location': 'L',
        'capacity': 10,
        'organizerId': 'org1',
        'organizerName': 'Org',
      });
      expect(event.isOrganizedBy('org1'), isTrue);
    });

    test('returns false for a different user id', () {
      final event = EventDoc.fromJson({
        '_id': 'evt1',
        'title': 'T',
        'startsAt': '2026-09-01T18:00:00.000Z',
        'location': 'L',
        'capacity': 10,
        'organizerId': 'org1',
        'organizerName': 'Org',
      });
      expect(event.isOrganizedBy('someone-else'), isFalse);
    });

    test('returns false for a null user id', () {
      final event = EventDoc.fromJson({
        '_id': 'evt1',
        'title': 'T',
        'startsAt': '2026-09-01T18:00:00.000Z',
        'location': 'L',
        'capacity': 10,
        'organizerId': 'org1',
        'organizerName': 'Org',
      });
      expect(event.isOrganizedBy(null), isFalse);
    });
  });
}
