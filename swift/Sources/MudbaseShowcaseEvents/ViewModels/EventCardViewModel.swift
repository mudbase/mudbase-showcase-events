import Foundation

/// One tiny view model per event card/detail header, fetching just that event's live confirmed
/// count — mirrors `useConfirmedCount(event._id)` being called independently inside `EventCard.tsx`
/// and `events/[id]/page.tsx` rather than the list batching every card's count together.
@MainActor
final class EventCardViewModel: ObservableObject {
    @Published private(set) var confirmedCount: Int?
    @Published private(set) var isLoading = true

    private let service: BookingsService
    private let eventId: String

    init(config: AppConfig, eventId: String) {
        service = BookingsService(config: config)
        self.eventId = eventId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        confirmedCount = try? await service.confirmedCount(eventId: eventId)
    }
}
