/// Mirrors the web app's `BookingStatus` union (`web/src/types/booking.ts`)
/// as a Dart `enum` (idiomatic per this project's Dart pattern rules -
/// sealed/enum types with exhaustive `switch`, rather than a raw string
/// field).
enum BookingStatus {
  confirmed,
  waitlisted,
  cancelled,
  checkedIn;

  static BookingStatus fromWire(String? value) {
    return switch (value) {
      'confirmed' => BookingStatus.confirmed,
      'waitlisted' => BookingStatus.waitlisted,
      'cancelled' => BookingStatus.cancelled,
      'checked_in' => BookingStatus.checkedIn,
      // A booking status is a closed, platform-validated enum on the server
      // (see `plan/build-plan.md`) - an unrecognized wire value would only
      // ever come from a client/server version skew, never legitimate data,
      // so this falls back to the safest read: treat it as cancelled (never
      // counts toward capacity, never displayed as a valid active ticket).
      _ => BookingStatus.cancelled,
    };
  }

  String get wireValue {
    return switch (this) {
      BookingStatus.confirmed => 'confirmed',
      BookingStatus.waitlisted => 'waitlisted',
      BookingStatus.cancelled => 'cancelled',
      BookingStatus.checkedIn => 'checked_in',
    };
  }

  String get label {
    return switch (this) {
      BookingStatus.confirmed => 'Confirmed',
      BookingStatus.waitlisted => 'Waitlisted',
      BookingStatus.cancelled => 'Cancelled',
      BookingStatus.checkedIn => 'Checked in',
    };
  }
}

/// Mirrors the web app's `BookingDoc` (`web/src/types/booking.ts`) and the
/// live `bookings` collection schema (`eventId`, `userId`, `userName`,
/// `status`, `qrToken`).
class Booking {
  const Booking({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.userName,
    required this.status,
    required this.qrToken,
    required this.createdAt,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['_id'] as String? ?? '',
      eventId: json['eventId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      status: BookingStatus.fromWire(json['status'] as String?),
      qrToken: json['qrToken'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String eventId;
  final String userId;
  final String userName;
  final BookingStatus status;
  final String qrToken;
  final DateTime createdAt;
}
