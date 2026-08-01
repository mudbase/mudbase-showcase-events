import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../data/repository_providers.dart';
import '../../../models/event.dart';
import '../../auth/auth_controller.dart';
import 'capacity_badge.dart';

/// Live confirmed-vs-capacity count for one event card - a small,
/// independently-loading `FutureProvider` per card rather than bundled into
/// the list's own fetch, matching the web app's `useConfirmedCount(eventId)`
/// being called once per `EventCard`.
final _confirmedCountProvider = FutureProvider.autoDispose.family<int, String>((
  ref,
  eventId,
) async {
  final authNotifier = ref.watch(authControllerProvider.notifier);
  final bookingRepo = ref.watch(bookingRepositoryProvider);
  return authNotifier.callAuthorized(
    (token) => bookingRepo.confirmedCount(token: token, eventId: eventId),
  );
});

class EventCard extends ConsumerWidget {
  const EventCard({required this.event, required this.onTap, super.key});

  final EventDoc event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final confirmedAsync = ref.watch(_confirmedCountProvider(event.id));

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      event.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  confirmedAsync.when(
                    data: (confirmed) => CapacityBadge(
                      confirmed: confirmed,
                      capacity: event.capacity,
                    ),
                    loading: () => CapacityBadge(
                      confirmed: null,
                      capacity: event.capacity,
                      isLoading: true,
                    ),
                    error: (error, stackTrace) => CapacityBadge(
                      confirmed: null,
                      capacity: event.capacity,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _InfoLine(
                icon: Icons.calendar_today_outlined,
                text: formatDateTime(event.startsAt),
              ),
              const SizedBox(height: 4),
              _InfoLine(icon: Icons.place_outlined, text: event.location),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
