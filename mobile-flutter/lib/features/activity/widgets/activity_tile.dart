import 'package:flutter/material.dart';

import '../../../core/activity_text.dart';
import '../../../core/formatters.dart';
import '../../../models/activity_entry.dart';

/// One row in an event's activity feed - mirrors the reference web app's
/// `ActivityFeed.tsx` list item (actor + action sentence + relative time).
class ActivityTile extends StatelessWidget {
  const ActivityTile({required this.entry, super.key});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _iconFor(entry.action),
          size: 18,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                describeActivity(entry),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                formatRelativeTime(entry.createdAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _iconFor(ActivityAction action) {
    return switch (action) {
      ActivityAction.bookingConfirmed => Icons.check_circle_outline,
      ActivityAction.bookingWaitlisted => Icons.hourglass_empty,
      ActivityAction.bookingCancelled => Icons.cancel_outlined,
      ActivityAction.bookingPromoted => Icons.arrow_upward,
      ActivityAction.checkedIn => Icons.qr_code_scanner,
      ActivityAction.eventCreated => Icons.add_circle_outline,
      ActivityAction.eventUpdated => Icons.edit_outlined,
      ActivityAction.unknown => Icons.circle_outlined,
    };
  }
}
