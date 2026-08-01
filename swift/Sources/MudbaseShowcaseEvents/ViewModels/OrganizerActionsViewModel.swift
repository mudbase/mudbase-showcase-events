import Foundation

/// Mirrors `OrganizerActions.tsx`'s delete action — the edit/check-in links are plain navigation,
/// handled by the view itself.
@MainActor
final class OrganizerActionsViewModel: ObservableObject {
    @Published private(set) var isDeleting = false
    @Published var errorMessage: String?
    @Published private(set) var didDelete = false

    private let service: EventsService
    private let eventId: String

    init(config: AppConfig, eventId: String) {
        service = EventsService(config: config)
        self.eventId = eventId
    }

    func delete() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await service.delete(id: eventId)
            didDelete = true
        } catch {
            errorMessage = "Couldn't delete this event. Please try again."
        }
    }
}
