import type { MudbaseClient } from "@/lib/mudbase"
import { BOOKINGS_COLLECTION_ID, ACTIVITY_COLLECTION_ID } from "@/lib/config"
import type { BookingDoc } from "@/types/booking"

// Generous ceiling on how many live (confirmed+waitlisted) bookings a single event can have for
// reconciliation purposes - well beyond any capacity this demo app's UI allows creating (see the
// create/edit event form's capacity field), so it never truncates the real data.
const RECONCILE_FETCH_LIMIT = 1000

/**
 * Re-derives which bookings for an event should hold a confirmed seat versus sit on the waitlist,
 * and patches only the ones whose current status disagrees with that derivation.
 *
 * Mudbase (a generic-CRUD BaaS) has no cross-document transactions or atomic counters, so a plain
 * "count confirmed, then create" is inherently racy: two simultaneous booking requests can both
 * read the same pre-write count and both decide "there's room". This function narrows that race
 * window by re-deriving truth from a fresh read (creation-order priority: the first `capacity`
 * bookings, oldest first, among confirmed+waitlisted, are the ones entitled to a seat) and
 * correcting any booking that disagrees - whether that means demoting an overshoot back to
 * waitlisted, or promoting the earliest waitlisted booking once a cancellation frees a seat.
 *
 * Deliberately excludes "checked_in" bookings from the capacity count (see build-plan.md
 * "Capacity-Race Handling Approach") - the task's spec defines capacity in terms of `"confirmed"`
 * bookings specifically, and running this after check-in would incorrectly free an already-seated
 * attendee's slot for someone else.
 */
export async function reconcileEventCapacity(client: MudbaseClient, eventId: string, capacity: number): Promise<void> {
  const [confirmedRes, waitlistedRes] = await Promise.all([
    client.getDocuments<BookingDoc>(BOOKINGS_COLLECTION_ID, {
      filter: { eventId, status: "confirmed" },
      sort: "createdAt",
      limit: RECONCILE_FETCH_LIMIT,
    }),
    client.getDocuments<BookingDoc>(BOOKINGS_COLLECTION_ID, {
      filter: { eventId, status: "waitlisted" },
      sort: "createdAt",
      limit: RECONCILE_FETCH_LIMIT,
    }),
  ])

  const live = [...confirmedRes.data, ...waitlistedRes.data].sort(
    (a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime(),
  )

  const corrections: Promise<unknown>[] = []

  live.forEach((booking, index) => {
    const shouldBeConfirmed = index < capacity

    if (shouldBeConfirmed && booking.status !== "confirmed") {
      corrections.push(
        client
          .updateDocument<BookingDoc>(BOOKINGS_COLLECTION_ID, booking._id, { status: "confirmed" })
          .then(() =>
            client.createDocument(ACTIVITY_COLLECTION_ID, {
              eventId,
              actorId: booking.userId,
              actorName: booking.userName,
              action: "booking_promoted",
            }),
          ),
      )
    } else if (!shouldBeConfirmed && booking.status !== "waitlisted") {
      corrections.push(
        client
          .updateDocument<BookingDoc>(BOOKINGS_COLLECTION_ID, booking._id, { status: "waitlisted" })
          .then(() =>
            client.createDocument(ACTIVITY_COLLECTION_ID, {
              eventId,
              actorId: booking.userId,
              actorName: booking.userName,
              action: "booking_waitlisted",
            }),
          ),
      )
    }
  })

  await Promise.all(corrections)
}
