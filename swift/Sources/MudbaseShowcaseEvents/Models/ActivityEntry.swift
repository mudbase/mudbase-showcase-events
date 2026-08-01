import Foundation

/// Mirrors `web/src/types/activity.ts`'s `ActivityAction` union and `ACTIVITY_LABELS` map exactly.
enum ActivityAction: String, Sendable, Equatable, CaseIterable {
    case bookingConfirmed = "booking_confirmed"
    case bookingWaitlisted = "booking_waitlisted"
    case bookingCancelled = "booking_cancelled"
    case bookingPromoted = "booking_promoted"
    case checkedIn = "checked_in"
    case eventCreated = "event_created"
    case eventUpdated = "event_updated"

    var label: String {
        switch self {
        case .bookingConfirmed: return "booked (confirmed)"
        case .bookingWaitlisted: return "joined the waitlist"
        case .bookingCancelled: return "cancelled their booking"
        case .bookingPromoted: return "was promoted from the waitlist"
        case .checkedIn: return "checked in"
        case .eventCreated: return "created this event"
        case .eventUpdated: return "updated this event"
        }
    }
}

/// Mirrors `web/src/types/activity.ts`'s `ActivityDoc` interface exactly.
struct ActivityEntry: Sendable, Equatable, Identifiable {
    let id: String
    let createdAt: Date?
    let eventId: String
    let actorId: String
    let actorName: String
    let action: ActivityAction

    /// Fails when `action` doesn't match a known case — a forward-compatible guard against a
    /// future action this build doesn't know about yet, rather than rendering a blank/garbled row.
    init?(document: MudbaseDocument) {
        guard let action = document.string("action").flatMap(ActivityAction.init(rawValue:)) else { return nil }
        id = document.id
        createdAt = document.createdAt
        eventId = document.string("eventId") ?? ""
        actorId = document.string("actorId") ?? ""
        actorName = document.string("actorName") ?? ""
        self.action = action
    }
}
