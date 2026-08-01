import Foundation

/// Mirrors `BookingList.tsx` — the signed-in attendee's own bookings across every event, joined
/// against each booking's event doc (since Mudbase has no native join) for the title/date/location
/// shown on each card.
@MainActor
final class MyBookingsViewModel: ObservableObject {
    @Published private(set) var bookings: [Booking] = []
    @Published private(set) var eventsById: [String: EventItem] = [:]
    @Published private(set) var isLoading = true
    @Published private(set) var cancellingBookingId: String?

    private let bookingsService: BookingsService
    private let eventsService: EventsService
    private let currentUser: AppUser

    init(config: AppConfig, currentUser: AppUser) {
        bookingsService = BookingsService(config: config)
        eventsService = EventsService(config: config)
        self.currentUser = currentUser
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            bookings = try await bookingsService.myBookings(userId: currentUser.id)
            eventsById = try await eventsService.get(ids: bookings.map(\.eventId))
        } catch {
            bookings = []
            eventsById = [:]
        }
    }

    var canCancel: (Booking) -> Bool {
        { booking in booking.status == .confirmed || booking.status == .waitlisted }
    }

    func cancel(_ booking: Booking) async {
        guard let event = eventsById[booking.eventId] else { return }
        cancellingBookingId = booking.id
        defer { cancellingBookingId = nil }
        do {
            try await bookingsService.cancelBooking(
                bookingId: booking.id,
                eventId: booking.eventId,
                capacity: event.capacity,
                userId: currentUser.id,
                userName: currentUser.displayName
            )
            await load()
        } catch {
            // Leave the list as-is on failure — the same Cancel button is available to retry, and
            // no partial state was mutated (cancelBooking itself either fully lands or throws before
            // its own reconciliation pass).
        }
    }
}
