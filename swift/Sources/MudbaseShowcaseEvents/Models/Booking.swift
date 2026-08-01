import Foundation

/// Mirrors `web/src/types/booking.ts`'s `BookingStatus` union exactly.
enum BookingStatus: String, Sendable, Equatable, CaseIterable {
    case confirmed
    case waitlisted
    case cancelled
    case checkedIn = "checked_in"

    var label: String {
        switch self {
        case .confirmed: return "Confirmed"
        case .waitlisted: return "Waitlisted"
        case .cancelled: return "Cancelled"
        case .checkedIn: return "Checked in"
        }
    }
}

/// Mirrors `web/src/types/booking.ts`'s `BookingDoc` interface exactly.
struct Booking: Sendable, Equatable, Identifiable {
    let id: String
    let createdAt: Date?
    let eventId: String
    let userId: String
    let userName: String
    let status: BookingStatus
    let qrToken: String

    init(document: MudbaseDocument) {
        id = document.id
        createdAt = document.createdAt
        eventId = document.string("eventId") ?? ""
        userId = document.string("userId") ?? ""
        userName = document.string("userName") ?? ""
        status = (document.string("status")).flatMap(BookingStatus.init(rawValue:)) ?? .waitlisted
        qrToken = document.string("qrToken") ?? ""
    }
}
