import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/formatters.dart';
import '../../../models/booking.dart';
import '../my_bookings_controller.dart';

/// One booking in the signed-in attendee's own bookings list, rendered with
/// a `QrImageView` of its `qrToken` (the Dart-native equivalent of the
/// reference web app's `qrcode.react`) and a Cancel action for still-active
/// bookings. Mirrors `BookingCard.tsx`.
class BookingCard extends StatelessWidget {
  const BookingCard({
    required this.item,
    required this.onCancel,
    this.busy = false,
    super.key,
  });

  final BookingWithEvent item;
  final VoidCallback onCancel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final booking = item.booking;
    final event = item.event;
    final canCancel =
        booking.status == BookingStatus.confirmed ||
        booking.status == BookingStatus.waitlisted;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event?.title ?? 'Event no longer available',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (event != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          formatDateTime(event.startsAt),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                _StatusBadge(status: booking.status),
              ],
            ),
            const SizedBox(height: 16),
            if (booking.status != BookingStatus.cancelled)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: booking.qrToken,
                    size: 160,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            if (canCancel) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: busy ? null : onCancel,
                  icon: const Icon(Icons.close),
                  label: Text(busy ? 'Cancelling…' : 'Cancel booking'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = switch (status) {
      BookingStatus.confirmed => (Colors.green.shade100, Colors.green.shade900),
      BookingStatus.checkedIn => (Colors.blue.shade100, Colors.blue.shade900),
      BookingStatus.waitlisted => (
        Colors.amber.shade100,
        Colors.amber.shade900,
      ),
      BookingStatus.cancelled => (
        Theme.of(context).colorScheme.surfaceContainerHighest,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
