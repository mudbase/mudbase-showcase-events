/// Mirrors the web app's `ActivityAction` union (`web/src/types/activity.ts`)
/// as a Dart `enum`. `unknown` is not written by this app but exists so
/// parsing a server row with an action value this client doesn't recognize
/// yet fails soft (see `ActivityEntry.fromJson`) instead of throwing.
enum ActivityAction {
  bookingConfirmed,
  bookingWaitlisted,
  bookingCancelled,
  bookingPromoted,
  checkedIn,
  eventCreated,
  eventUpdated,
  unknown;

  static ActivityAction fromWire(String? value) {
    return switch (value) {
      'booking_confirmed' => ActivityAction.bookingConfirmed,
      'booking_waitlisted' => ActivityAction.bookingWaitlisted,
      'booking_cancelled' => ActivityAction.bookingCancelled,
      'booking_promoted' => ActivityAction.bookingPromoted,
      'checked_in' => ActivityAction.checkedIn,
      'event_created' => ActivityAction.eventCreated,
      'event_updated' => ActivityAction.eventUpdated,
      _ => ActivityAction.unknown,
    };
  }

  String get wireValue {
    return switch (this) {
      ActivityAction.bookingConfirmed => 'booking_confirmed',
      ActivityAction.bookingWaitlisted => 'booking_waitlisted',
      ActivityAction.bookingCancelled => 'booking_cancelled',
      ActivityAction.bookingPromoted => 'booking_promoted',
      ActivityAction.checkedIn => 'checked_in',
      ActivityAction.eventCreated => 'event_created',
      ActivityAction.eventUpdated => 'event_updated',
      ActivityAction.unknown => 'unknown',
    };
  }
}

/// Mirrors the web app's `ActivityDoc` (`web/src/types/activity.ts`) and the
/// live `activity` collection schema (`eventId`, `actorId`, `actorName`,
/// `action`). Fetched `sort: "-createdAt"` for the reverse-chronological
/// feed - see `ActivityRepository.listForEvent`.
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.eventId,
    required this.actorId,
    required this.actorName,
    required this.action,
    required this.createdAt,
  });

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    return ActivityEntry(
      id: json['_id'] as String? ?? '',
      eventId: json['eventId'] as String? ?? '',
      actorId: json['actorId'] as String? ?? '',
      actorName: json['actorName'] as String? ?? '',
      action: ActivityAction.fromWire(json['action'] as String?),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String eventId;
  final String actorId;
  final String actorName;
  final ActivityAction action;
  final DateTime createdAt;
}
