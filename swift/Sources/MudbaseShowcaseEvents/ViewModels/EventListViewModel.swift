import Foundation

/// Mirrors `EventList.tsx` + `useEvents(page)` — paginated, soonest-first event list. Per-card
/// confirmed-vs-capacity counts are fetched independently by each `EventCardView` (see
/// `EventCardViewModel`), matching the web app's `EventCard.tsx` calling `useConfirmedCount` itself
/// rather than the list batching it.
@MainActor
final class EventListViewModel: ObservableObject {
    @Published private(set) var events: [EventItem] = []
    @Published private(set) var page = 1
    @Published private(set) var totalPages = 1
    @Published private(set) var hasMore = false
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    private let service: EventsService

    init(config: AppConfig) {
        service = EventsService(config: config)
    }

    func load(page: Int = 1) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await service.list(page: page)
            events = result.events
            self.page = result.page
            totalPages = result.totalPages
            hasMore = result.hasMore
        } catch {
            errorMessage = "Couldn't load events. Please sign in and try again."
        }
    }

    func nextPage() async {
        guard hasMore else { return }
        await load(page: page + 1)
    }

    func previousPage() async {
        guard page > 1 else { return }
        await load(page: page - 1)
    }
}
