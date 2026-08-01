import '../../config/env_config.dart';
import '../../core/mudbase_data_service.dart';
import '../../models/event.dart';

class EventRepository {
  const EventRepository(this._dataService);

  final MudbaseDataService _dataService;

  /// One page of events, ascending by `startsAt` (soonest first) - mirrors
  /// the web app's `useEvents(page)` (`sort: "startsAt"`, `limit: 10`).
  Future<List<EventDoc>> list({
    required String token,
    int page = 1,
    int limit = 10,
  }) async {
    final docs = await _dataService.list(
      EnvConfig.eventsCollectionId,
      token: token,
      sort: 'startsAt',
      page: page,
      limit: limit,
    );
    return docs.map(EventDoc.fromJson).toList();
  }

  Future<EventDoc> getById({
    required String token,
    required String eventId,
  }) async {
    final doc = await _dataService.getById(
      EnvConfig.eventsCollectionId,
      eventId,
      token: token,
    );
    if (doc == null) {
      throw StateError('Event $eventId was not found.');
    }
    return EventDoc.fromJson(doc);
  }

  /// Organizer-only: creates a new event.
  Future<EventDoc> create({
    required String token,
    required String title,
    String? description,
    required DateTime startsAt,
    required String location,
    required int capacity,
    required String organizerId,
    required String organizerName,
  }) async {
    final doc = await _dataService.create(EnvConfig.eventsCollectionId, {
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      'startsAt': startsAt.toUtc().toIso8601String(),
      'location': location,
      'capacity': capacity,
      'organizerId': organizerId,
      'organizerName': organizerName,
    }, token: token);
    return EventDoc.fromJson(doc);
  }

  /// Organizer-only (own events): edits an event's details. Not itself
  /// responsible for re-checking capacity against existing bookings - the
  /// caller (`EventDetailController.updateEvent`) runs the shared
  /// reconciliation pass afterward, same as the web app's edit page
  /// documents ("Changes to capacity are re-checked against existing
  /// bookings").
  Future<EventDoc> update({
    required String token,
    required String eventId,
    required String title,
    String? description,
    required DateTime startsAt,
    required String location,
    required int capacity,
  }) async {
    final doc = await _dataService
        .update(EnvConfig.eventsCollectionId, eventId, {
          'title': title,
          'description': description ?? '',
          'startsAt': startsAt.toUtc().toIso8601String(),
          'location': location,
          'capacity': capacity,
        }, token: token);
    return EventDoc.fromJson(doc);
  }

  /// Organizer-only (own events): deletes an event.
  Future<void> delete({required String token, required String eventId}) async {
    await _dataService.delete(
      EnvConfig.eventsCollectionId,
      eventId,
      token: token,
    );
  }
}
