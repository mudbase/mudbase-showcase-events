import '../../config/env_config.dart';
import '../../core/mudbase_data_service.dart';
import '../../models/booking.dart';

class BookingRepository {
  const BookingRepository(this._dataService);

  final MudbaseDataService _dataService;

  /// Generous ceiling on how many live (confirmed+waitlisted) bookings a
  /// single event can have for reconciliation purposes - well beyond any
  /// capacity this app's create/edit event form allows creating, so it
  /// never truncates the real data. Mirrors the web app's
  /// `RECONCILE_FETCH_LIMIT` (`web/src/lib/capacity.ts`).
  static const int reconcileFetchLimit = 1000;

  /// Every booking for one event, optionally filtered to a single [status].
  Future<List<Booking>> listForEvent({
    required String token,
    required String eventId,
    String? status,
    String sort = '-createdAt',
    int limit = 100,
  }) async {
    final docs = await _dataService.list(
      EnvConfig.bookingsCollectionId,
      token: token,
      filter: {'eventId': eventId, if (status != null) 'status': status},
      sort: sort,
      limit: limit,
    );
    return docs.map(Booking.fromJson).toList();
  }

  /// The signed-in attendee's own bookings across every event, newest first
  /// - mirrors the web app's `useMyBookings`.
  Future<List<Booking>> listForUser({
    required String token,
    required String userId,
    int limit = 100,
  }) async {
    final docs = await _dataService.list(
      EnvConfig.bookingsCollectionId,
      token: token,
      filter: {'userId': userId},
      sort: '-createdAt',
      limit: limit,
    );
    return docs.map(Booking.fromJson).toList();
  }

  /// The signed-in user's own bookings for one specific event, newest
  /// first, so the caller can find the currently-active one (status !=
  /// cancelled) - mirrors the web app's `useMyBookingForEvent` intent (used
  /// to hide the Book button / show its status instead).
  Future<List<Booking>> listForEventAndUser({
    required String token,
    required String eventId,
    required String userId,
    int limit = 10,
  }) async {
    final docs = await _dataService.list(
      EnvConfig.bookingsCollectionId,
      token: token,
      filter: {'eventId': eventId, 'userId': userId},
      sort: '-createdAt',
      limit: limit,
    );
    return docs.map(Booking.fromJson).toList();
  }

  /// A real server-side count of confirmed bookings for one event - the
  /// same "decide, then reconcile" capacity-race approach the web app's
  /// `useConfirmedCount`/`useCreateBooking` documents (see
  /// `plan/build-plan.md` "Capacity-Race Handling Approach").
  Future<int> confirmedCount({required String token, required String eventId}) {
    return _dataService.count(
      EnvConfig.bookingsCollectionId,
      token: token,
      filter: {'eventId': eventId, 'status': 'confirmed'},
    );
  }

  Future<Booking> getById({
    required String token,
    required String bookingId,
  }) async {
    final doc = await _dataService.getById(
      EnvConfig.bookingsCollectionId,
      bookingId,
      token: token,
    );
    if (doc == null) {
      throw StateError('Booking $bookingId was not found.');
    }
    return Booking.fromJson(doc);
  }

  /// Looks up a booking by its scanned/pasted `qrToken` within one event -
  /// mirrors the web app's `useCheckIn` lookup.
  Future<Booking?> findByQrToken({
    required String token,
    required String eventId,
    required String qrToken,
  }) async {
    final docs = await _dataService.list(
      EnvConfig.bookingsCollectionId,
      token: token,
      filter: {'eventId': eventId, 'qrToken': qrToken},
      limit: 1,
    );
    if (docs.isEmpty) return null;
    return Booking.fromJson(docs.first);
  }

  Future<Booking> create({
    required String token,
    required String eventId,
    required String userId,
    required String userName,
    required BookingStatus status,
    required String qrToken,
  }) async {
    final doc = await _dataService.create(EnvConfig.bookingsCollectionId, {
      'eventId': eventId,
      'userId': userId,
      'userName': userName,
      'status': status.wireValue,
      'qrToken': qrToken,
    }, token: token);
    return Booking.fromJson(doc);
  }

  Future<Booking> updateStatus({
    required String token,
    required String bookingId,
    required BookingStatus status,
  }) async {
    final doc = await _dataService.update(
      EnvConfig.bookingsCollectionId,
      bookingId,
      {'status': status.wireValue},
      token: token,
    );
    return Booking.fromJson(doc);
  }
}
