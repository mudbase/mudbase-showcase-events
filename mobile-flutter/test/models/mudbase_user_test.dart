import 'package:mudbase_showcase_events/models/mudbase_user.dart';
import 'package:test/test.dart';

void main() {
  group('MudbaseUser.fromJson', () {
    test('parses a full user object', () {
      final user = MudbaseUser.fromJson({
        'id': 'u1',
        'email': 'events.organizer.demo@gmail.com',
        'firstName': 'Ola',
        'lastName': 'Organizer',
        'customRole': 'organizer',
        'emailVerified': true,
      });

      expect(user.id, 'u1');
      expect(user.email, 'events.organizer.demo@gmail.com');
      expect(user.customRole, 'organizer');
      expect(user.emailVerified, isTrue);
    });

    test('falls back to _id when id is absent', () {
      final user = MudbaseUser.fromJson({'_id': 'u2', 'email': 'a@b.com'});
      expect(user.id, 'u2');
    });
  });

  group('MudbaseUser.fullName', () {
    test('joins first and last name', () {
      const user = MudbaseUser(
        id: 'u1',
        email: 'a@b.com',
        firstName: 'Ola',
        lastName: 'Organizer',
        customRole: 'organizer',
        emailVerified: true,
      );
      expect(user.fullName, 'Ola Organizer');
    });

    test('falls back to email when both names are empty', () {
      const user = MudbaseUser(
        id: 'u1',
        email: 'a@b.com',
        firstName: '',
        lastName: '',
        customRole: 'attendee',
        emailVerified: true,
      );
      expect(user.fullName, 'a@b.com');
    });
  });
}
