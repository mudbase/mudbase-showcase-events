import Foundation

/// Mirrors `ActivityFeed.tsx` + `useEventActivity` — reverse-chronological activity feed for one
/// event.
@MainActor
final class ActivityFeedViewModel: ObservableObject {
    @Published private(set) var entries: [ActivityEntry] = []
    @Published private(set) var isLoading = true

    private let service: ActivityService
    private let eventId: String

    init(config: AppConfig, eventId: String) {
        service = ActivityService(config: config)
        self.eventId = eventId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        entries = (try? await service.list(eventId: eventId)) ?? []
    }
}
