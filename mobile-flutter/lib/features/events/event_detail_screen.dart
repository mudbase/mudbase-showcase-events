import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/mudbase_exception.dart';
import '../../models/booking.dart';
import '../../widgets/async_value_view.dart';
import '../activity/widgets/activity_tile.dart';
import '../auth/auth_controller.dart';
import 'event_detail_controller.dart';
import 'widgets/capacity_badge.dart';

/// Full event detail - mirrors the reference web app's `/events/[id]` page:
/// info, live capacity indicator, a Book/booking-status affordance, the
/// organizer-only actions row (edit / check-in / delete) when the viewer
/// owns the event, and the reverse-chronological activity feed.
class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({required this.eventId, super.key});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailState = ref.watch(eventDetailControllerProvider(eventId));

    return Scaffold(
      appBar: AppBar(title: const Text('Event')),
      body: AsyncValueView<EventDetailData>(
        value: detailState,
        onRetry: () => ref.invalidate(eventDetailControllerProvider(eventId)),
        data: (context, data) => _EventDetailBody(eventId: eventId, data: data),
      ),
    );
  }
}

class _EventDetailBody extends ConsumerStatefulWidget {
  const _EventDetailBody({required this.eventId, required this.data});

  final String eventId;
  final EventDetailData data;

  @override
  ConsumerState<_EventDetailBody> createState() => _EventDetailBodyState();
}

class _EventDetailBodyState extends ConsumerState<_EventDetailBody> {
  bool _busy = false;
  String? _bookingFeedback;
  bool _confirmingDelete = false;

  EventDetailController get _controller =>
      ref.read(eventDetailControllerProvider(widget.eventId).notifier);

  Future<void> _book() async {
    setState(() {
      _busy = true;
      _bookingFeedback = null;
    });
    try {
      final status = await _controller.book();
      setState(() {
        _bookingFeedback = status == BookingStatus.confirmed
            ? "You're confirmed! See your ticket under My bookings."
            : "This event is full — you've been added to the waitlist.";
      });
    } on Object {
      setState(
        () => _bookingFeedback =
            "Couldn't complete your booking. Please try again.",
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await _controller.cancelMyBooking();
    } on MudbaseException catch (error) {
      _showSnack(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() {
      _confirmingDelete = false;
      _busy = true;
    });
    try {
      await _controller.deleteEvent();
      if (mounted) context.go('/events');
    } on MudbaseException catch (error) {
      _showSnack(error.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final event = data.event;
    final user = ref.watch(authControllerProvider).valueOrNull;
    final isOwner = event.isOrganizedBy(user?.id);
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                event.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            CapacityBadge(
              confirmed: data.confirmedCount,
              capacity: event.capacity,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Hosted by ${event.organizerName}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _InfoRow(
          icon: Icons.calendar_today_outlined,
          text: formatDateTime(event.startsAt),
        ),
        const SizedBox(height: 6),
        _InfoRow(icon: Icons.place_outlined, text: event.location),
        const SizedBox(height: 6),
        _InfoRow(
          icon: Icons.people_outline,
          text: 'Capacity: ${event.capacity}',
        ),
        if (event.description != null && event.description!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            event.description!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 20),
        _bookingSection(context, isOwner, data),
        if (isOwner) ...[
          const SizedBox(height: 16),
          _organizerActions(context),
        ],
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        Text('Activity', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (data.activity.isEmpty)
          Text(
            'No activity yet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          )
        else
          Column(
            children: [
              for (final entry in data.activity) ...[
                ActivityTile(entry: entry),
                if (entry != data.activity.last) const Divider(height: 24),
              ],
            ],
          ),
      ],
    );
  }

  Widget _bookingSection(
    BuildContext context,
    bool isOwner,
    EventDetailData data,
  ) {
    if (isOwner) return const SizedBox.shrink();
    final user = ref.watch(authControllerProvider).valueOrNull;
    if (user == null) {
      return ElevatedButton(
        onPressed: () => context.push('/login'),
        child: const Text('Sign in to book'),
      );
    }

    final booking = data.myActiveBooking;
    if (booking != null) {
      final statusLabel = switch (booking.status) {
        BookingStatus.confirmed => "You're booked",
        BookingStatus.waitlisted => "You're on the waitlist",
        BookingStatus.checkedIn => "You're checked in",
        BookingStatus.cancelled => 'Booking cancelled',
      };
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _StatusPill(
            label: statusLabel,
            isWarning: booking.status == BookingStatus.waitlisted,
          ),
          OutlinedButton(
            onPressed: () => context.push('/bookings'),
            child: const Text('View my bookings'),
          ),
          if (booking.status != BookingStatus.checkedIn)
            TextButton(
              onPressed: _busy ? null : _cancel,
              child: Text(_busy ? 'Cancelling…' : 'Cancel booking'),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton(
          onPressed: _busy ? null : _book,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Book this event'),
        ),
        if (_bookingFeedback != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _bookingFeedback!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _organizerActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ORGANIZER',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.push('/events/${widget.eventId}/edit'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    context.push('/events/${widget.eventId}/checkin'),
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('Check-in'),
              ),
              if (_confirmingDelete)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Delete permanently?',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed: _busy ? null : _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                      child: Text(_busy ? 'Deleting…' : 'Confirm'),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _confirmingDelete = false),
                      child: const Text('Cancel'),
                    ),
                  ],
                )
              else
                OutlinedButton.icon(
                  onPressed: () => setState(() => _confirmingDelete = true),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: colorScheme.error,
                  ),
                  label: Text(
                    'Delete',
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.isWarning});

  final String label;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final background = isWarning
        ? Colors.amber.shade100
        : Colors.green.shade100;
    final foreground = isWarning
        ? Colors.amber.shade900
        : Colors.green.shade900;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
