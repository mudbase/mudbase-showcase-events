import '../models/activity_entry.dart';

/// Renders one activity row as a plain, readable sentence for the feed.
/// Mirrors `ACTIVITY_LABELS` in `web/src/types/activity.ts` (the web app
/// renders `"{actorName} {label}"` directly in `ActivityFeed.tsx`), with one
/// addition: an `ActivityAction.unknown` arm for forward compatibility with
/// a server-sent `action` value this client doesn't recognize yet.
String describeActivity(ActivityEntry entry) {
  final who = entry.actorName.isNotEmpty ? entry.actorName : 'Someone';
  final label = switch (entry.action) {
    ActivityAction.bookingConfirmed => 'booked (confirmed)',
    ActivityAction.bookingWaitlisted => 'joined the waitlist',
    ActivityAction.bookingCancelled => 'cancelled their booking',
    ActivityAction.bookingPromoted => 'was promoted from the waitlist',
    ActivityAction.checkedIn => 'checked in',
    ActivityAction.eventCreated => 'created this event',
    ActivityAction.eventUpdated => 'updated this event',
    ActivityAction.unknown => 'did something on this event',
  };
  return '$who $label';
}
