import '../../config/env_config.dart';
import '../../core/mudbase_data_service.dart';
import '../../models/activity_entry.dart';

class ActivityRepository {
  const ActivityRepository(this._dataService);

  final MudbaseDataService _dataService;

  static const int feedLimit = 50;

  /// Reverse-chronological activity feed for one event.
  Future<List<ActivityEntry>> listForEvent({
    required String token,
    required String eventId,
  }) async {
    final docs = await _dataService.list(
      EnvConfig.activityCollectionId,
      token: token,
      filter: {'eventId': eventId},
      sort: '-createdAt',
      limit: feedLimit,
    );
    return docs.map(ActivityEntry.fromJson).toList();
  }

  /// Appends one activity row. Every event/booking mutation this app
  /// performs calls this immediately after its own write succeeds - see
  /// `EventDetailController` and `lib/core/capacity.dart`.
  Future<void> log({
    required String token,
    required String eventId,
    required String actorId,
    required String actorName,
    required ActivityAction action,
  }) async {
    await _dataService.create(EnvConfig.activityCollectionId, {
      'eventId': eventId,
      'actorId': actorId,
      'actorName': actorName,
      'action': action.wireValue,
    }, token: token);
  }
}
