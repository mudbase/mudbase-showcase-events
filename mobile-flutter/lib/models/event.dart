/// Mirrors the web app's `EventDoc` (`web/src/types/event.ts`) and the live
/// `events` collection schema (`title`, `description?`, `startsAt`,
/// `location`, `capacity`, `organizerId`, `organizerName`).
class EventDoc {
  const EventDoc({
    required this.id,
    required this.title,
    this.description,
    required this.startsAt,
    required this.location,
    required this.capacity,
    required this.organizerId,
    required this.organizerName,
    required this.createdAt,
  });

  factory EventDoc.fromJson(Map<String, dynamic> json) {
    return EventDoc(
      id: json['_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      startsAt:
          DateTime.tryParse(json['startsAt'] as String? ?? '') ??
          DateTime.now(),
      location: json['location'] as String? ?? '',
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      organizerId: json['organizerId'] as String? ?? '',
      organizerName: json['organizerName'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String title;
  final String? description;
  final DateTime startsAt;
  final String location;
  final int capacity;
  final String organizerId;
  final String organizerName;
  final DateTime createdAt;

  bool isOrganizedBy(String? userId) => userId != null && userId == organizerId;
}
