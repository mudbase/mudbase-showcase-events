import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/rbac.dart';
import '../../widgets/async_value_view.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/role_badge.dart';
import '../auth/auth_controller.dart';
import 'events_controller.dart';
import 'widgets/event_card.dart';

/// Paginated event list - mirrors the reference web app's `/` page. Each
/// card shows a live confirmed-vs-capacity indicator; organizers additionally
/// see a "New event" affordance (UI gating only, see `core/rbac.dart`).
class EventsListScreen extends ConsumerStatefulWidget {
  const EventsListScreen({super.key});

  @override
  ConsumerState<EventsListScreen> createState() => _EventsListScreenState();
}

class _EventsListScreenState extends ConsumerState<EventsListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      ref.read(eventsListControllerProvider.notifier).loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventsState = ref.watch(eventsListControllerProvider);
    final user = ref.watch(authControllerProvider).valueOrNull;
    final role = user?.customRole;
    final canCreate = canManageEvents(role);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
        actions: [
          if (role != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: RoleBadge(role: role)),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(eventsListControllerProvider.notifier).refresh(),
        child: AsyncValueView<EventsPage>(
          value: eventsState,
          onRetry: () => ref.invalidate(eventsListControllerProvider),
          data: (context, page) {
            if (page.events.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.event_busy_outlined,
                    message: 'No events yet.',
                  ),
                ],
              );
            }
            return ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: page.events.length + (page.hasMore ? 1 : 0),
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index >= page.events.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final event = page.events[index];
                return EventCard(
                  event: event,
                  onTap: () => context.push('/events/${event.id}'),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/events/new'),
              icon: const Icon(Icons.add),
              label: const Text('New event'),
            )
          : null,
    );
  }
}
