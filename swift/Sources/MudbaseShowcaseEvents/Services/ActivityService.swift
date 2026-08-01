import Foundation
import MudbaseSDK

/// Reads and writes against the `activity` collection. Mirrors `web/src/hooks/useActivity.ts`
/// (`useEventActivity`) for reads, and the inline `client.createDocument(ACTIVITY_COLLECTION_ID, …)`
/// calls scattered across `useBookings.ts`/`capacity.ts`/the event create/edit pages for writes —
/// centralized here into one `log` method since every call site writes the same four fields.
struct ActivityService: Sendable {
    private let gateway: CollectionsGateway

    init(config: AppConfig) {
        gateway = CollectionsGateway(projectId: config.projectId, collectionId: config.activityCollectionId)
    }

    /// Reverse-chronological activity feed for one event: booking created, cancelled, promoted,
    /// checked in, event created/updated. Mirrors `useEventActivity`'s `sort: "-createdAt", limit: 50`.
    func list(eventId: String) async throws -> [ActivityEntry] {
        let result = try await gateway.list(filter: ["eventId": .string(eventId)], sort: "-createdAt", limit: 50)
        return result.documents.compactMap(ActivityEntry.init(document:))
    }

    @discardableResult
    func log(eventId: String, actorId: String, actorName: String, action: ActivityAction) async throws -> ActivityEntry? {
        let document = try await gateway.create(fields: [
            "eventId": .string(eventId),
            "actorId": .string(actorId),
            "actorName": .string(actorName),
            "action": .string(action.rawValue),
        ])
        return ActivityEntry(document: document)
    }
}
