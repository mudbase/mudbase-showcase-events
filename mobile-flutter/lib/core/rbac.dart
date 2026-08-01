/// Client-side mirror of the RBAC matrix Mudbase's own collection
/// permissions already enforce server-side (see `plan/build-plan.md` and
/// the reference web app's `plan/build-plan.md` "RBAC Matrix"). This exists
/// purely to hide/disable controls a role cannot use and to show a clear
/// reason why - it is NOT the security boundary. A raw API call bypassing
/// this app's UI entirely is still rejected by the platform; see
/// `tool/manual_test.dart` for a live proof (an attendee-token raw event
/// update attempt, 403).
library;

/// Role slugs this project's multi-role auth is configured with. Kept as
/// plain `String` constants (not a Dart `enum`) because the wire value
/// (`user.customRole`) is exactly one of these two strings already - no
/// translation layer needed between JSON and app state.
abstract final class AppRole {
  const AppRole._();

  static const String organizer = 'organizer';
  static const String attendee = 'attendee';
}

bool isAppRole(String? value) {
  return value == AppRole.organizer || value == AppRole.attendee;
}

/// Create/update/delete an event, and check attendees in via QR token -
/// server-enforced (only the event's own `organizerId` may write it, see
/// `EventDetailController`), this is UX gating so the right affordances show.
bool canManageEvents(String? role) => role == AppRole.organizer;

/// Every signed-in user (organizer or attendee) can book a spot and manage
/// their own bookings - there is no read-only role in this app's RBAC
/// matrix (unlike the sibling kanban port's `viewer`).
bool canBook(String? role) => isAppRole(role);

String roleLabel(String? role) {
  return switch (role) {
    AppRole.organizer => 'Organizer',
    AppRole.attendee => 'Attendee',
    _ => 'Unknown',
  };
}
