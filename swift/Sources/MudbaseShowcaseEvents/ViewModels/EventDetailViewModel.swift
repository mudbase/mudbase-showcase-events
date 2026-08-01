import Foundation

/// Mirrors `events/[id]/page.tsx` + `BookButton.tsx` combined: loads the event, its live confirmed
/// count, and the signed-in user's own booking for it (if any), and drives the book action.
@MainActor
final class EventDetailViewModel: ObservableObject {
    @Published private(set) var event: EventItem?
    @Published private(set) var confirmedCount: Int?
    @Published private(set) var myBooking: Booking?
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingBooking = true
    @Published private(set) var isBooking = false
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var bookingFeedback: String?

    private let eventsService: EventsService
    private let bookingsService: BookingsService
    private let eventId: String
    private let currentUser: AppUser

    init(config: AppConfig, eventId: String, currentUser: AppUser) {
        eventsService = EventsService(config: config)
        bookingsService = BookingsService(config: config)
        self.eventId = eventId
        self.currentUser = currentUser
    }

    var isOwnEvent: Bool { event?.organizerId == currentUser.id }

    /// The user's own booking for this event, unless it's `cancelled` — a re-bookable state.
    /// Mirrors `BookButton.tsx`'s `existing?.data.find(b => b.status !== "cancelled")`: the same
    /// user can end up with more than one booking document for the same event if they cancel and
    /// then book again, and only the non-cancelled one should hide the Book button.
    var activeBooking: Booking? {
        guard let myBooking, myBooking.status != .cancelled else { return nil }
        return myBooking
    }

    func load() async {
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }
        do {
            event = try await eventsService.get(id: eventId)
        } catch {
            loadErrorMessage = "Event not found."
            return
        }
        await loadConfirmedCount()
        await loadMyBooking()
    }

    func loadConfirmedCount() async {
        confirmedCount = try? await bookingsService.confirmedCount(eventId: eventId)
    }

    func loadMyBooking() async {
        guard !isOwnEvent else {
            myBooking = nil
            isLoadingBooking = false
            return
        }
        isLoadingBooking = true
        defer { isLoadingBooking = false }
        myBooking = try? await bookingsService.myBooking(eventId: eventId, userId: currentUser.id)
    }

    func book() async {
        guard let event else { return }
        isBooking = true
        bookingFeedback = nil
        defer { isBooking = false }
        do {
            let booking = try await bookingsService.createBooking(
                eventId: event.id,
                capacity: event.capacity,
                userId: currentUser.id,
                userName: currentUser.displayName
            )
            myBooking = booking
            bookingFeedback = booking.status == .confirmed
                ? "You're confirmed! See your ticket under My bookings."
                : "This event is full — you've been added to the waitlist."
            await loadConfirmedCount()
        } catch {
            bookingFeedback = "Couldn't complete your booking. Please try again."
        }
    }
}
