import Foundation
import Testing
@testable import MudbaseShowcaseEvents
import MudbaseSDK

/// Standalone, headless verification that exercises this app's own `Services`/`Networking` layer —
/// the exact `AuthGateway`, `EventsService`, `BookingsService`, `ActivityService`, and
/// `AccessTokenCoordinator` types the SwiftUI views and view models call — directly against the
/// real, live `cloud.mudbase.dev` project. There is no iOS Simulator in this environment, so this
/// stands in for clicking through the actual UI (the same headless-verification approach used to
/// build the ecommerce/social Swift ports).
///
/// Disabled unless `RUN_LIVE_FLOW_TEST=1` is set, since it makes real network calls against a live
/// project and writes real documents (events, bookings, activity entries) — a plain `swift test`
/// must never do that on its own. Run it explicitly with:
///
///   RUN_LIVE_FLOW_TEST=1 swift test --filter ManualLiveFlowTests
@Suite(.serialized)
struct ManualLiveFlowTests {
    static let isEnabled = ProcessInfo.processInfo.environment["RUN_LIVE_FLOW_TEST"] == "1"

    static let config = AppConfig(
        projectId: "6a6d3fa9d07caabbbdfc564f",
        baseURL: URL(string: "https://cloud.mudbase.dev")!,
        eventsCollectionId: "6a6d3fcad07caabbbdfc5802",
        bookingsCollectionId: "6a6d3fcbd07caabbbdfc5819",
        activityCollectionId: "6a6d3fccd07caabbbdfc582e"
    )

    /// The two shared, already-verified seed accounts documented in the events README — used
    /// directly rather than self-registering fresh accounts, since `/login` has a far more generous
    /// per-IP rate-limit budget than the signup endpoint, and both roles must be exercised in every
    /// language port's own live-flow harness against this same project.
    static let organizerEmail = "events.organizer.demo@gmail.com"
    static let attendeeEmail = "events.attendee.demo@gmail.com"
    static let sharedPassword = "DemoTest123!"

    enum HarnessError: Error, CustomStringConvertible {
        case missingSessionInResponse

        var description: String {
            "login response had no token/refreshToken"
        }
    }

    @Test(.enabled(if: ManualLiveFlowTests.isEnabled))
    @MainActor
    func fullEventBookingFlow() async throws {
        MudbaseSDKBootstrap.configure(baseURL: Self.config.baseURL)

        let authGateway = AuthGateway(projectId: Self.config.projectId)
        let eventsService = EventsService(config: Self.config)
        let bookingsService = BookingsService(config: Self.config)
        let activityService = ActivityService(config: Self.config)

        // --- Organizer: sign in, create a capacity-2 event ---
        let organizerSession = try await authGateway.login(email: Self.organizerEmail, password: Self.sharedPassword)
        MudbaseSDKBootstrap.setAccessToken(organizerSession.accessToken)
        let organizer = try await authGateway.currentUser()
        #expect(organizer.role == .organizer, "expected the organizer demo account's customRole to be \"organizer\", got \(String(describing: organizer.role))")

        var draft = EventDraft()
        draft.title = "Swift Manual Test Event \(UUID().uuidString.prefix(8))"
        draft.description = "Created by Tests/ManualLiveFlowTests — safe to delete."
        draft.startsAt = Date().addingTimeInterval(86_400)
        draft.location = "Test Hall"
        draft.capacity = 2
        let event = try await eventsService.create(draft: draft, organizerId: organizer.id, organizerName: organizer.displayName)
        #expect(event.capacity == 2)

        // --- Attendee: sign in, read the list, book into the event twice (fills capacity), then a
        // third time (should waitlist) ---
        let attendeeSession = try await authGateway.login(email: Self.attendeeEmail, password: Self.sharedPassword)
        MudbaseSDKBootstrap.setAccessToken(attendeeSession.accessToken)
        let attendee = try await authGateway.currentUser()
        #expect(attendee.role == .attendee, "expected the attendee demo account's customRole to be \"attendee\", got \(String(describing: attendee.role))")

        let page = try await eventsService.list(page: 1)
        #expect(!page.events.isEmpty, "event list read returned no events at all")

        // Booking #1 — this exact attendee account, fills seat 1 of 2.
        let firstBooking = try await bookingsService.createBooking(eventId: event.id, capacity: event.capacity, userId: attendee.id, userName: attendee.displayName)
        #expect(firstBooking.status == .confirmed, "first booking on an empty capacity-2 event should be confirmed, got \(firstBooking.status)")

        // Booking #2 — same attendee account booking a second, distinct slot (simulating a second
        // guest) by writing directly through the bookings gateway with a synthetic second userId
        // isn't possible without a second real account, so instead this exercises the reconciliation
        // pass directly: force-write a second and third "confirmed" booking under the same real
        // attendee id (Mudbase's collection schema doesn't uniqueness-constrain userId+eventId), then
        // confirm reconciliation demotes the excess one back to waitlisted — the same race-simulation
        // approach the web app's own live smoke test used.
        let secondBookingId = try await Self.forceConfirmedBooking(eventId: event.id, userId: attendee.id, userName: attendee.displayName, config: Self.config)
        let thirdBookingId = try await Self.forceConfirmedBooking(eventId: event.id, userId: attendee.id, userName: attendee.displayName, config: Self.config)

        try await bookingsService.reconcileCapacity(eventId: event.id, capacity: event.capacity)

        let confirmedAfterReconcile = try await bookingsService.confirmedCount(eventId: event.id)
        #expect(confirmedAfterReconcile == event.capacity, "reconciliation should leave exactly \(event.capacity) confirmed bookings, found \(confirmedAfterReconcile)")

        // --- Cancellation promotes the earliest waitlisted booking ---
        try await bookingsService.cancelBooking(bookingId: firstBooking.id, eventId: event.id, capacity: event.capacity, userId: attendee.id, userName: attendee.displayName)
        let confirmedAfterCancel = try await bookingsService.confirmedCount(eventId: event.id)
        #expect(confirmedAfterCancel == event.capacity, "cancelling one confirmed booking should promote a waitlisted one to backfill capacity")

        // --- Check-in: organizer looks up a still-confirmed booking by its qrToken ---
        MudbaseSDKBootstrap.setAccessToken(organizerSession.accessToken)
        let remainingBookings = try await bookingsService.myBookings(userId: attendee.id)
        let confirmedBooking = remainingBookings.first { $0.status == .confirmed && $0.eventId == event.id }
        if let confirmedBooking {
            let outcome = try await bookingsService.checkIn(eventId: event.id, qrToken: confirmedBooking.qrToken)
            if case .checkedIn = outcome {
                // expected
            } else {
                Issue.record("expected check-in to succeed for a confirmed booking, got \(outcome)")
            }

            // Idempotent re-check-in.
            let secondOutcome = try await bookingsService.checkIn(eventId: event.id, qrToken: confirmedBooking.qrToken)
            if case .alreadyCheckedIn = secondOutcome {
                // expected
            } else {
                Issue.record("expected a second check-in on the same token to report already_checked_in, got \(secondOutcome)")
            }
        } else {
            Issue.record("no confirmed booking remained to check in — reconciliation/cancellation assertions above should have guaranteed one")
        }

        // Not-found check-in.
        let notFoundOutcome = try await bookingsService.checkIn(eventId: event.id, qrToken: "this-token-does-not-exist")
        #expect(notFoundOutcome == .notFound)

        // --- Activity feed reflects everything above, reverse-chronological ---
        let activity = try await activityService.list(eventId: event.id)
        #expect(activity.contains { $0.action == .eventCreated })
        #expect(activity.contains { $0.action == .bookingConfirmed })
        #expect(activity.contains { $0.action == .bookingCancelled })
        #expect(activity.contains { $0.action == .checkedIn })

        // --- 401 refresh-and-retry: force the in-memory access token invalid, keep the real refresh
        // token in a scratch Keychain entry, and confirm `AccessTokenCoordinator` transparently
        // refreshes and retries once instead of the call failing outright. ---
        let scratchTokenStore = KeychainTokenStore(service: "dev.mudbase.showcase.events.manualtest")
        scratchTokenStore.save(.init(accessToken: organizerSession.accessToken, refreshToken: organizerSession.refreshToken))
        await AccessTokenCoordinator.shared.configure(authGateway: authGateway, tokenStore: scratchTokenStore)
        MudbaseSDKBootstrap.setAccessToken("this-access-token-is-intentionally-invalid")
        let eventAfterForcedExpiry = try await eventsService.get(id: event.id)
        #expect(eventAfterForcedExpiry.id == event.id, "a call made with a deliberately invalid access token did not recover via refresh-and-retry")
        scratchTokenStore.clear()

        // --- Cleanup: delete the test event (organizer-owned; bookings/activity rows are orphaned
        // but harmless — this project has no cascade-delete, matching the web app's own behavior) ---
        MudbaseSDKBootstrap.setAccessToken(organizerSession.accessToken)
        try await eventsService.delete(id: event.id)
        _ = secondBookingId
        _ = thirdBookingId

        try? await authGateway.logout()
    }

    /// Writes a booking document directly through `CollectionsGateway`, bypassing
    /// `BookingsService.createBooking`'s own capacity check — used only to simulate the race
    /// condition (multiple concurrent requests landing "confirmed" before reconciliation runs) the
    /// same way the web app's own live smoke test did, since this harness has only one real
    /// attendee account to drive with.
    private static func forceConfirmedBooking(eventId: String, userId: String, userName: String, config: AppConfig) async throws -> String {
        let gateway = CollectionsGateway(projectId: config.projectId, collectionId: config.bookingsCollectionId)
        let document = try await gateway.create(fields: [
            "eventId": .string(eventId),
            "userId": .string(userId),
            "userName": .string(userName),
            "status": .string("confirmed"),
            "qrToken": .string(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()),
        ])
        return document.id
    }
}
