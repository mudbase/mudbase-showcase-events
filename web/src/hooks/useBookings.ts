"use client"

import { useMutation } from "@tanstack/react-query"
import { BOOKINGS_COLLECTION_ID, ACTIVITY_COLLECTION_ID } from "@/lib/config"
import { useMudbase } from "@/lib/mudbase-provider"
import { useDocuments } from "@/hooks/useCollection"
import { useInvalidateEventState } from "@/hooks/useEvents"
import { reconcileEventCapacity } from "@/lib/capacity"
import { generateQrToken } from "@/lib/utils"
import type { BookingDoc, BookingStatus } from "@/types/booking"

/** The signed-in attendee's own bookings across every event, newest first. */
export function useMyBookings(userId: string | null | undefined) {
  return useDocuments<BookingDoc>(
    BOOKINGS_COLLECTION_ID,
    { filter: { userId: userId ?? "" }, sort: "-createdAt", limit: 100 },
    { enabled: !!userId },
  )
}

/** The signed-in user's own booking for one specific event, if any (used to hide the Book button / show its status instead). */
export function useMyBookingForEvent(eventId: string | null | undefined, userId: string | null | undefined) {
  return useDocuments<BookingDoc>(
    BOOKINGS_COLLECTION_ID,
    { filter: { eventId: eventId ?? "", userId: userId ?? "" }, limit: 1 },
    { enabled: !!eventId && !!userId },
  )
}

export interface CreateBookingInput {
  eventId: string
  capacity: number
  userId: string
  userName: string
}

/**
 * Creates a booking using the capacity-race approach documented in plan/build-plan.md: decide the
 * initial status from a fresh server-side confirmed count, write it, then run the shared
 * reconciliation pass so a race against another concurrent booking self-corrects. Returns the
 * booking's *post-reconciliation* state, not its tentative initial write, so the UI never reports
 * a status that got corrected out from under it a moment later.
 */
export function useCreateBooking() {
  const { client } = useMudbase()
  const invalidate = useInvalidateEventState()

  return useMutation<BookingDoc, Error, CreateBookingInput>({
    mutationFn: async ({ eventId, capacity, userId, userName }) => {
      const confirmedRes = await client.getDocuments<BookingDoc>(BOOKINGS_COLLECTION_ID, {
        filter: { eventId, status: "confirmed" },
        limit: 1,
      })
      const initialStatus: BookingStatus = confirmedRes.pagination.total < capacity ? "confirmed" : "waitlisted"
      const qrToken = generateQrToken()

      const booking = await client.createDocument<BookingDoc>(BOOKINGS_COLLECTION_ID, {
        eventId,
        userId,
        userName,
        status: initialStatus,
        qrToken,
      })

      await client.createDocument(ACTIVITY_COLLECTION_ID, {
        eventId,
        actorId: userId,
        actorName: userName,
        action: initialStatus === "confirmed" ? "booking_confirmed" : "booking_waitlisted",
      })

      await reconcileEventCapacity(client, eventId, capacity)

      // Re-read: reconciliation above may have demoted this exact booking if it lost a race
      // against another concurrent request that also decided "confirmed" from the same
      // pre-write count.
      return client.getDocument<BookingDoc>(BOOKINGS_COLLECTION_ID, booking._id)
    },
    onSuccess: (_booking, { eventId }) => invalidate(eventId),
  })
}

export interface CancelBookingInput {
  bookingId: string
  eventId: string
  capacity: number
  userId: string
  userName: string
}

/** Cancels an attendee's own booking, then reconciles so the earliest waitlisted booking is promoted into the freed seat. */
export function useCancelBooking() {
  const { client } = useMudbase()
  const invalidate = useInvalidateEventState()

  return useMutation<void, Error, CancelBookingInput>({
    mutationFn: async ({ bookingId, eventId, capacity, userId, userName }) => {
      await client.updateDocument<BookingDoc>(BOOKINGS_COLLECTION_ID, bookingId, { status: "cancelled" })
      await client.createDocument(ACTIVITY_COLLECTION_ID, {
        eventId,
        actorId: userId,
        actorName: userName,
        action: "booking_cancelled",
      })
      await reconcileEventCapacity(client, eventId, capacity)
    },
    onSuccess: (_data, { eventId }) => invalidate(eventId),
  })
}

export type CheckInOutcome = "checked_in" | "already_checked_in" | "cancelled" | "waitlisted" | "not_found"

export interface CheckInResult {
  outcome: CheckInOutcome
  booking?: BookingDoc
}

export interface CheckInInput {
  eventId: string
  qrToken: string
}

/** Looks up a booking by its scanned/pasted qrToken within one event and, if eligible, checks it in. */
export function useCheckIn() {
  const { client } = useMudbase()
  const invalidate = useInvalidateEventState()

  return useMutation<CheckInResult, Error, CheckInInput>({
    mutationFn: async ({ eventId, qrToken }) => {
      const trimmed = qrToken.trim()
      if (!trimmed) return { outcome: "not_found" }

      const res = await client.getDocuments<BookingDoc>(BOOKINGS_COLLECTION_ID, {
        filter: { eventId, qrToken: trimmed },
        limit: 1,
      })
      const booking = res.data[0]
      if (!booking) return { outcome: "not_found" }
      if (booking.status === "checked_in") return { outcome: "already_checked_in", booking }
      if (booking.status === "cancelled") return { outcome: "cancelled", booking }
      if (booking.status === "waitlisted") return { outcome: "waitlisted", booking }

      const updated = await client.updateDocument<BookingDoc>(BOOKINGS_COLLECTION_ID, booking._id, {
        status: "checked_in",
      })
      await client.createDocument(ACTIVITY_COLLECTION_ID, {
        eventId,
        actorId: booking.userId,
        actorName: booking.userName,
        action: "checked_in",
      })
      return { outcome: "checked_in", booking: updated }
    },
    onSuccess: (result, { eventId }) => {
      if (result.outcome === "checked_in") invalidate(eventId)
    },
  })
}
