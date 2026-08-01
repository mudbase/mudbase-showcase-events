import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repository_providers.dart';
import '../../models/activity_entry.dart';
import '../../models/event.dart';
import '../auth/auth_controller.dart';

/// One loaded "page" of the events list, plus enough bookkeeping to drive an
/// infinite-scroll / "load more" UI - the mobile-appropriate adaptation of
/// the reference web app's numbered pagination (`page`/`limit` query
/// params), which this app still issues under the hood (see
/// `EventRepository.list`).
class EventsPage {
  const EventsPage({
    required this.events,
    required this.page,
    required this.hasMore,
  });

  final List<EventDoc> events;
  final int page;
  final bool hasMore;

  EventsPage appending(EventsPage next) {
    return EventsPage(
      events: [...events, ...next.events],
      page: next.page,
      hasMore: next.hasMore,
    );
  }
}

/// Owns the paginated event list plus event creation - mirrors the
/// reference web app's `useEvents(page)` + `useCreateEvent`.
class EventsListController extends AsyncNotifier<EventsPage> {
  static const int pageSize = 10;

  @override
  Future<EventsPage> build() => _fetchPage(1);

  Future<EventsPage> _fetchPage(int page) async {
    final authNotifier = ref.read(authControllerProvider.notifier);
    final repo = ref.read(eventRepositoryProvider);
    final events = await authNotifier.callAuthorized(
      (token) => repo.list(token: token, page: page, limit: pageSize),
    );
    return EventsPage(
      events: events,
      page: page,
      hasMore: events.length == pageSize,
    );
  }

  Future<void> refresh() async {
    try {
      state = AsyncData(await _fetchPage(1));
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> loadNextPage() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;
    try {
      final next = await _fetchPage(current.page + 1);
      state = AsyncData(current.appending(next));
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// Organizer-only (enforced server-side; the "New event" affordance is
  /// also hidden for attendees in the UI - see `core/rbac.dart`). Logs an
  /// `event_created` activity row immediately after the write succeeds,
  /// mirroring the web app's `/events/new` page (the activity log call
  /// lives in the page component there too, not inside `useCreateEvent`).
  Future<EventDoc> createEvent({
    required String title,
    String? description,
    required DateTime startsAt,
    required String location,
    required int capacity,
  }) async {
    final user = ref.read(authControllerProvider).valueOrNull;
    if (user == null) throw StateError('Must be signed in to create an event.');
    final authNotifier = ref.read(authControllerProvider.notifier);
    final eventRepo = ref.read(eventRepositoryProvider);
    final activityRepo = ref.read(activityRepositoryProvider);

    final created = await authNotifier.callAuthorized((token) async {
      final event = await eventRepo.create(
        token: token,
        title: title,
        description: description,
        startsAt: startsAt,
        location: location,
        capacity: capacity,
        organizerId: user.id,
        organizerName: user.fullName,
      );
      await activityRepo.log(
        token: token,
        eventId: event.id,
        actorId: user.id,
        actorName: user.fullName,
        action: ActivityAction.eventCreated,
      );
      return event;
    });
    await refresh();
    return created;
  }
}

final eventsListControllerProvider =
    AsyncNotifierProvider<EventsListController, EventsPage>(
      EventsListController.new,
    );
