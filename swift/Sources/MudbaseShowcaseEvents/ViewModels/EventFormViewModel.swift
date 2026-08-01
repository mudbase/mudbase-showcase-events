import Foundation

/// Mirrors `EventForm.tsx`'s zod schema — re-implemented as plain validation since this project has
/// no zod dependency. Handles both "New event" and "Edit event" (an `existingEvent` switches the
/// save path from `create` to `update`, exactly like `events/new/page.tsx` vs.
/// `events/[id]/edit/page.tsx`).
@MainActor
final class EventFormViewModel: ObservableObject {
    @Published var draft: EventDraft
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    @Published private(set) var didSave = false
    @Published private(set) var savedEvent: EventItem?

    private let service: EventsService
    private let existingEventId: String?
    private let actorId: String
    private let actorName: String

    init(config: AppConfig, existingEvent: EventItem?, actorId: String, actorName: String) {
        service = EventsService(config: config)
        existingEventId = existingEvent?.id
        draft = existingEvent.map(EventDraft.init(event:)) ?? EventDraft()
        self.actorId = actorId
        self.actorName = actorName
    }

    var isEditing: Bool { existingEventId != nil }

    private var validationError: String? {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespaces)
        if trimmedTitle.isEmpty { return "Title is required" }
        if trimmedTitle.count > 200 { return "Title is too long" }
        if draft.description.count > 2000 { return "Description is too long" }
        let trimmedLocation = draft.location.trimmingCharacters(in: .whitespaces)
        if trimmedLocation.isEmpty { return "Location is required" }
        if trimmedLocation.count > 200 { return "Location is too long" }
        if draft.capacity < 1 { return "Capacity must be at least 1" }
        if draft.capacity > 100_000 { return "Capacity is unrealistically large" }
        return nil
    }

    func save() async {
        if let validationError {
            errorMessage = validationError
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            if let existingEventId {
                savedEvent = try await service.update(id: existingEventId, draft: draft, actorId: actorId, actorName: actorName)
            } else {
                savedEvent = try await service.create(draft: draft, organizerId: actorId, organizerName: actorName)
            }
            didSave = true
        } catch {
            errorMessage = isEditing ? "Couldn't save these changes. Please try again." : "Couldn't create this event. Please try again."
        }
    }
}
