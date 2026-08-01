import Foundation
import MudbaseSDK

/// Booking CRUD, capacity-aware create, cancel-triggered waitlist promotion, and QR-token check-in
/// against the `bookings` collection. This is the Swift port of `web/src/hooks/useBookings.ts` +
/// `web/src/lib/capacity.ts` combined — every algorithmic decision here (initial status on create,
/// the reconciliation pass, what check-in does and does NOT do) mirrors those two files exactly; see
/// each method's doc comment for the specific web-side function it replicates.
struct BookingsService: Sendable {
    private let gateway: CollectionsGateway
    private let activity: ActivityService

    /// Generous ceiling on how many live (confirmed+waitlisted) bookings a single event can have for
    /// reconciliation purposes — well beyond any capacity this app's create/edit event form allows,
    /// so it never truncates the real data. Mirrors `capacity.ts`'s `RECONCILE_FETCH_LIMIT`.
    private static let reconcileFetchLimit = 1000

    init(config: AppConfig) {
        gateway = CollectionsGateway(projectId: config.projectId, collectionId: config.bookingsCollectionId)
        activity = ActivityService(config: config)
    }

    /// The live confirmed-booking count for one event, for the capacity indicator on its card/
    /// detail. Mirrors `useConfirmedCount` — reads `pagination.total` from a `limit: 1` query rather
    /// than fetching (and counting) every confirmed booking.
    func confirmedCount(eventId: String) async throws -> Int {
        let result = try await gateway.list(filter: ["eventId": .string(eventId), "status": .string("confirmed")], limit: 1)
        return result.pagination?.total ?? 0
    }

    /// The signed-in attendee's own bookings across every event, newest first. Mirrors `useMyBookings`.
    func myBookings(userId: String) async throws -> [Booking] {
        let result = try await gateway.list(filter: ["userId": .string(userId)], sort: "-createdAt", limit: 100)
        return result.documents.map(Booking.init(document:))
    }

    /// The signed-in user's own booking for one specific event, if any — used to hide the Book
    /// button / show its status instead. Mirrors `useMyBookingForEvent`.
    func myBooking(eventId: String, userId: String) async throws -> Booking? {
        let result = try await gateway.list(filter: ["eventId": .string(eventId), "userId": .string(userId)], limit: 1)
        return result.documents.first.map(Booking.init(document:))
    }

    /// Creates a booking using the capacity-race approach documented in `web/plan/build-plan.md`
    /// "Capacity-Race Handling Approach": decide the initial status from a fresh server-side
    /// confirmed count, write it, then run the shared reconciliation pass so a race against another
    /// concurrent booking self-corrects. Returns the booking's *post-reconciliation* state, not its
    /// tentative initial write, so the caller never reports a status that got corrected out from
    /// under it a moment later. Mirrors `useCreateBooking`'s `mutationFn` exactly.
    @discardableResult
    func createBooking(eventId: String, capacity: Int, userId: String, userName: String) async throws -> Booking {
        let confirmedResult = try await gateway.list(filter: ["eventId": .string(eventId), "status": .string("confirmed")], limit: 1)
        let confirmedTotal = confirmedResult.pagination?.total ?? 0
        let initialStatus: BookingStatus = confirmedTotal < capacity ? .confirmed : .waitlisted
        let qrToken = Self.generateQrToken()

        let created = try await gateway.create(fields: [
            "eventId": .string(eventId),
            "userId": .string(userId),
            "userName": .string(userName),
            "status": .string(initialStatus.rawValue),
            "qrToken": .string(qrToken),
        ])

        try await activity.log(
            eventId: eventId,
            actorId: userId,
            actorName: userName,
            action: initialStatus == .confirmed ? .bookingConfirmed : .bookingWaitlisted
        )

        try await reconcileCapacity(eventId: eventId, capacity: capacity)

        // Re-read: reconciliation above may have demoted this exact booking if it lost a race
        // against another concurrent request that also decided "confirmed" from the same pre-write
        // count.
        return Booking(document: try await gateway.get(documentId: created.id))
    }

    /// Cancels an attendee's own booking, then reconciles so the earliest waitlisted booking is
    /// promoted into the freed seat. Mirrors `useCancelBooking`.
    func cancelBooking(bookingId: String, eventId: String, capacity: Int, userId: String, userName: String) async throws {
        try await gateway.update(documentId: bookingId, fields: ["status": .string(BookingStatus.cancelled.rawValue)])
        try await activity.log(eventId: eventId, actorId: userId, actorName: userName, action: .bookingCancelled)
        try await reconcileCapacity(eventId: eventId, capacity: capacity)
    }

    enum CheckInOutcome: Equatable {
        case checkedIn(Booking)
        case alreadyCheckedIn(Booking)
        case cancelled(Booking)
        case waitlisted(Booking)
        case notFound
    }

    /// Looks up a booking by its scanned/pasted `qrToken` within one event and, if eligible, checks
    /// it in. Mirrors `useCheckIn` exactly, including which statuses are no-ops (idempotent) versus
    /// which one actually mutates. Deliberately does NOT run `reconcileCapacity` afterward — see
    /// that method's doc comment for why.
    func checkIn(eventId: String, qrToken: String) async throws -> CheckInOutcome {
        let trimmed = qrToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notFound }

        let result = try await gateway.list(filter: ["eventId": .string(eventId), "qrToken": .string(trimmed)], limit: 1)
        guard let document = result.documents.first else { return .notFound }
        let booking = Booking(document: document)

        switch booking.status {
        case .checkedIn:
            return .alreadyCheckedIn(booking)
        case .cancelled:
            return .cancelled(booking)
        case .waitlisted:
            return .waitlisted(booking)
        case .confirmed:
            let updated = try await gateway.update(documentId: booking.id, fields: ["status": .string(BookingStatus.checkedIn.rawValue)])
            try await activity.log(eventId: eventId, actorId: booking.userId, actorName: booking.userName, action: .checkedIn)
            return .checkedIn(Booking(document: updated))
        }
    }

    /// Re-derives which bookings for an event should hold a confirmed seat versus sit on the
    /// waitlist, and patches only the ones whose current status disagrees with that derivation.
    ///
    /// Mudbase (a generic-CRUD BaaS) has no cross-document transactions or atomic counters, so a
    /// plain "count confirmed, then create" is inherently racy: two simultaneous booking requests
    /// can both read the same pre-write count and both decide "there's room". This narrows that race
    /// window by re-deriving truth from a fresh read (creation-order priority: the first `capacity`
    /// bookings, oldest first, among confirmed+waitlisted, are the ones entitled to a seat) and
    /// correcting any booking that disagrees — whether that means demoting an overshoot back to
    /// waitlisted, or promoting the earliest waitlisted booking once a cancellation frees a seat.
    ///
    /// Deliberately excludes `checked_in` (and `cancelled`) bookings from the capacity count — the
    /// spec defines capacity in terms of `confirmed` bookings specifically, and running this after
    /// check-in would incorrectly free an already-seated attendee's slot for someone else on the
    /// waitlist while they're still physically present. This is a line-for-line port of
    /// `capacity.ts`'s `reconcileEventCapacity`.
    func reconcileCapacity(eventId: String, capacity: Int) async throws {
        async let confirmedResult = gateway.list(
            filter: ["eventId": .string(eventId), "status": .string("confirmed")],
            sort: "createdAt",
            limit: Self.reconcileFetchLimit
        )
        async let waitlistedResult = gateway.list(
            filter: ["eventId": .string(eventId), "status": .string("waitlisted")],
            sort: "createdAt",
            limit: Self.reconcileFetchLimit
        )

        let (confirmed, waitlisted) = try await (confirmedResult, waitlistedResult)
        let live = (confirmed.documents + waitlisted.documents)
            .map(Booking.init(document:))
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }

        let gateway = self.gateway
        let activity = self.activity

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, booking) in live.enumerated() {
                let shouldBeConfirmed = index < capacity

                if shouldBeConfirmed && booking.status != .confirmed {
                    group.addTask {
                        try await gateway.update(documentId: booking.id, fields: ["status": .string(BookingStatus.confirmed.rawValue)])
                        try await activity.log(eventId: eventId, actorId: booking.userId, actorName: booking.userName, action: .bookingPromoted)
                    }
                } else if !shouldBeConfirmed && booking.status != .waitlisted {
                    group.addTask {
                        try await gateway.update(documentId: booking.id, fields: ["status": .string(BookingStatus.waitlisted.rawValue)])
                        try await activity.log(eventId: eventId, actorId: booking.userId, actorName: booking.userName, action: .bookingWaitlisted)
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    /// A random, unguessable single-use check-in code. Mirrors `web/src/lib/utils.ts`'s
    /// `generateQrToken` (`crypto.randomUUID().replace(/-/g, "")`) — `UUID()`'s 122 bits of entropy
    /// is more than sufficient for a demo ticketing app's QR check-in token, same as the web side.
    private static func generateQrToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}
