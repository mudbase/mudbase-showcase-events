import Foundation

/// Mirrors `web/src/types/event.ts`'s `EventDoc` interface exactly — same field names, same
/// optionality (`description` is the only optional field).
struct EventItem: Sendable, Equatable, Identifiable {
    let id: String
    let createdAt: Date?
    let title: String
    let description: String?
    let startsAt: Date
    let location: String
    let capacity: Int
    let organizerId: String
    let organizerName: String

    init(document: MudbaseDocument) {
        id = document.id
        createdAt = document.createdAt
        title = document.string("title") ?? ""
        description = document.string("description")
        startsAt = document.date("startsAt") ?? Date()
        location = document.string("location") ?? ""
        capacity = document.int("capacity") ?? 0
        organizerId = document.string("organizerId") ?? ""
        organizerName = document.string("organizerName") ?? ""
    }
}

/// Draft state for the organizer's create/edit event form — the Swift equivalent of the web app's
/// zod-validated `EventFormValues` (`web/src/components/events/EventForm.tsx`). Validation is
/// re-implemented in `EventFormViewModel` since this project has no zod dependency.
struct EventDraft: Equatable {
    var title = ""
    var description = ""
    /// Defaults one hour out, matching a sensible "new event starts soon" default; the web form has
    /// no default `startsAt` (it's required with no prefill), but a native date picker needs some
    /// initial value to display.
    var startsAt = Date().addingTimeInterval(3600)
    var location = ""
    var capacity = 20

    init() {}

    init(event: EventItem) {
        title = event.title
        description = event.description ?? ""
        startsAt = event.startsAt
        location = event.location
        capacity = event.capacity
    }
}
