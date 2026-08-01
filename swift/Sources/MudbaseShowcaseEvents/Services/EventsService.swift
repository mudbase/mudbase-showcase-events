import Foundation
import MudbaseSDK

/// Event CRUD against the `events` collection. Mirrors `web/src/hooks/useEvents.ts`
/// (`useEvents`/`useEvent`/`useCreateEvent`/`useUpdateEvent`/`useDeleteEvent`) plus the
/// `event_created`/`event_updated` activity-log calls that live inline in
/// `events/new/page.tsx`/`events/[id]/edit/page.tsx` on the web side.
struct EventsService: Sendable {
    private let gateway: CollectionsGateway
    private let activity: ActivityService

    private static let pageSize = 10

    init(config: AppConfig) {
        gateway = CollectionsGateway(projectId: config.projectId, collectionId: config.eventsCollectionId)
        activity = ActivityService(config: config)
    }

    struct Page: Sendable {
        let events: [EventItem]
        let page: Int
        let totalPages: Int
        let hasMore: Bool
    }

    /// Mirrors `useEvents(page)` — `sort: "startsAt"` (soonest first), paginated 10 at a time.
    func list(page: Int) async throws -> Page {
        let result = try await gateway.list(sort: "startsAt", page: page, limit: Self.pageSize)
        let events = result.documents.map(EventItem.init(document:))
        let pagination = result.pagination
        let totalPages = pagination?.totalPages ?? (events.isEmpty ? 1 : page)
        let currentPage = pagination?.page ?? page
        let hasMore = currentPage < totalPages
        return Page(events: events, page: currentPage, totalPages: totalPages, hasMore: hasMore)
    }

    func get(id: String) async throws -> EventItem {
        EventItem(document: try await gateway.get(documentId: id))
    }

    /// Resolves a set of event ids (e.g. from the current user's bookings) to their full event
    /// docs, for the "My bookings" screen which needs to join booking rows against event details
    /// without a native join in a generic-CRUD BaaS — mirrors `useEventsByIds`. Fetches concurrently
    /// and silently drops any id that fails to resolve (e.g. a since-deleted event) rather than
    /// failing the whole join.
    func get(ids: [String]) async throws -> [String: EventItem] {
        let uniqueIds = Array(Set(ids))
        var result: [String: EventItem] = [:]
        try await withThrowingTaskGroup(of: (String, EventItem?).self) { group in
            for id in uniqueIds {
                group.addTask {
                    let event = try? await self.get(id: id)
                    return (id, event)
                }
            }
            for try await (id, event) in group {
                if let event { result[id] = event }
            }
        }
        return result
    }

    @discardableResult
    func create(draft: EventDraft, organizerId: String, organizerName: String) async throws -> EventItem {
        var fields = Self.commonFields(for: draft)
        fields["organizerId"] = .string(organizerId)
        fields["organizerName"] = .string(organizerName)
        let created = EventItem(document: try await gateway.create(fields: fields))
        try await activity.log(eventId: created.id, actorId: organizerId, actorName: organizerName, action: .eventCreated)
        return created
    }

    @discardableResult
    func update(id: String, draft: EventDraft, actorId: String, actorName: String) async throws -> EventItem {
        let updated = EventItem(document: try await gateway.update(documentId: id, fields: Self.commonFields(for: draft)))
        try await activity.log(eventId: id, actorId: actorId, actorName: actorName, action: .eventUpdated)
        return updated
    }

    func delete(id: String) async throws {
        try await gateway.delete(documentId: id)
    }

    /// `description` is dropped entirely (not sent as an explicit clear) when empty, matching
    /// `events/[id]/edit/page.tsx`'s `description: values.description || undefined` — see
    /// `JSONValue.object`'s doc comment for why an omitted key, not a null, is the faithful port.
    /// Shared by both `create` (which layers `organizerId`/`organizerName` on top) and `update`
    /// (which never touches those owner fields).
    private static func commonFields(for draft: EventDraft) -> [String: JSONValue?] {
        [
            "title": .string(draft.title),
            "description": draft.description.isEmpty ? nil : .string(draft.description),
            "startsAt": .string(ISO8601DateFormatter.mudbase.string(from: draft.startsAt)),
            "location": .string(draft.location),
            "capacity": .int(draft.capacity),
        ]
    }
}
