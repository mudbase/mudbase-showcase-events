import 'package:mudbase_showcase_events/core/rbac.dart';
import 'package:test/test.dart';

void main() {
  group('isAppRole', () {
    test('accepts organizer and attendee', () {
      expect(isAppRole(AppRole.organizer), isTrue);
      expect(isAppRole(AppRole.attendee), isTrue);
    });

    test('rejects unknown or null roles', () {
      expect(isAppRole('viewer'), isFalse);
      expect(isAppRole(null), isFalse);
    });
  });

  group('canManageEvents', () {
    test('true only for organizer', () {
      expect(canManageEvents(AppRole.organizer), isTrue);
      expect(canManageEvents(AppRole.attendee), isFalse);
      expect(canManageEvents(null), isFalse);
    });
  });

  group('canBook', () {
    test('true for both known roles, false otherwise', () {
      expect(canBook(AppRole.organizer), isTrue);
      expect(canBook(AppRole.attendee), isTrue);
      expect(canBook(null), isFalse);
      expect(canBook('viewer'), isFalse);
    });
  });

  group('roleLabel', () {
    test('maps each role to its display label', () {
      expect(roleLabel(AppRole.organizer), 'Organizer');
      expect(roleLabel(AppRole.attendee), 'Attendee');
      expect(roleLabel(null), 'Unknown');
      expect(roleLabel('bogus'), 'Unknown');
    });
  });
}
