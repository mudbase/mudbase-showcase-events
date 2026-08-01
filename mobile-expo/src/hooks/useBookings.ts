import { useCallback } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { mudbaseClient } from "@/api/client";
import { bookingDocSchema, activityEntrySchema, type BookingDoc, type BookingStatus } from "@/api/schemas";
import { BOOKINGS_COLLECTION_ID, ACTIVITY_COLLECTION_ID } from "@/config/env";
import { useInvalidateEventState } from "@/hooks/useEvents";
import { reconcileEventCapacity } from "@/lib/capacity";
import { generateQrToken } from "@/lib/format";

/** The signed-in attendee's own bookings across every event, newest first. Mirrors
 * web/src/hooks/useBookings.ts's useMyBookings. */
export function useMyBookings(userId: string | null | undefined) {
  return useQuery({
    queryKey: ["collection", BOOKINGS_COLLECTION_ID, { userId }],
    queryFn: () =>
      mudbaseClient.listDocuments(bookingDocSchema, BOOKINGS_COLLECTION_ID, {
        filter: { userId: userId ?? "" },
        sort: "-createdAt",
        limit: 100,
      }),
    enabled: !!userId,
  });
}

/** The signed-in user's own booking for one specific event, if any (used to hide the Book button
 * / show its status instead). Mirrors web/src/hooks/useBookings.ts's useMyBookingForEvent. */
export function useMyBookingForEvent(eventId: string | null | undefined, userId: string | null | undefined) {
  return useQuery({
    queryKey: ["collection", BOOKINGS_COLLECTION_ID, { eventId, userId }],
    queryFn: () =>
      mudbaseClient.listDocuments(bookingDocSchema, BOOKINGS_COLLECTION_ID, {
        filter: { eventId: eventId ?? "", userId: userId ?? "" },
        limit: 1,
      }),
    enabled: !!eventId && !!userId,
  });
}

export interface CreateBookingInput {
  eventId: string;
  capacity: number;
  userId: string;
  userName: string;
}

/**
 * Creates a booking using the capacity-race approach documented in web/plan/build-plan.md: decide
 * the initial status from a fresh server-side confirmed count, write it, then run the shared
 * reconciliation pass so a race against another concurrent booking self-corrects. Returns the
 * booking's *post-reconciliation* state, not its tentative initial write, so the UI never reports
 * a status that got corrected out from under it a moment later.
 */
export function useCreateBooking() {
  const invalidate = useInvalidateEventState();

  const mutate = useCallback(
    async ({ eventId, capacity, userId, userName }: CreateBookingInput): Promise<BookingDoc> => {
      const confirmedRes = await mudbaseClient.listDocuments(bookingDocSchema, BOOKINGS_COLLECTION_ID, {
        filter: { eventId, status: "confirmed" },
        limit: 1,
      });
      const initialStatus: BookingStatus = confirmedRes.pagination.total < capacity ? "confirmed" : "waitlisted";
      const qrToken = generateQrToken();

      const booking = await mudbaseClient.createDocument(bookingDocSchema, BOOKINGS_COLLECTION_ID, {
        eventId,
        userId,
        userName,
        status: initialStatus,
        qrToken,
      });

      await mudbaseClient.createDocument(activityEntrySchema, ACTIVITY_COLLECTION_ID, {
        eventId,
        actorId: userId,
        actorName: userName,
        action: initialStatus === "confirmed" ? "booking_confirmed" : "booking_waitlisted",
      });

      await reconcileEventCapacity(eventId, capacity);

      // Re-read: reconciliation above may have demoted this exact booking if it lost a race
      // against another concurrent request that also decided "confirmed" from the same
      // pre-write count.
      return mudbaseClient.getDocument(bookingDocSchema, BOOKINGS_COLLECTION_ID, booking._id);
    },
    [],
  );

  return useMutation({
    mutationFn: mutate,
    onSuccess: (_booking, { eventId }) => invalidate(eventId),
  });
}

export interface CancelBookingInput {
  bookingId: string;
  eventId: string;
  capacity: number;
  userId: string;
  userName: string;
}

/** Cancels an attendee's own booking, then reconciles so the earliest waitlisted booking is
 * promoted into the freed seat. Mirrors web/src/hooks/useBookings.ts's useCancelBooking. */
export function useCancelBooking() {
  const invalidate = useInvalidateEventState();

  const mutate = useCallback(
    async ({ bookingId, eventId, capacity, userId, userName }: CancelBookingInput): Promise<void> => {
      await mudbaseClient.updateDocument(bookingDocSchema, BOOKINGS_COLLECTION_ID, bookingId, {
        status: "cancelled",
      });
      await mudbaseClient.createDocument(activityEntrySchema, ACTIVITY_COLLECTION_ID, {
        eventId,
        actorId: userId,
        actorName: userName,
        action: "booking_cancelled",
      });
      await reconcileEventCapacity(eventId, capacity);
    },
    [],
  );

  return useMutation({
    mutationFn: mutate,
    onSuccess: (_data, { eventId }) => invalidate(eventId),
  });
}

export type CheckInOutcome = "checked_in" | "already_checked_in" | "cancelled" | "waitlisted" | "not_found";

export interface CheckInResult {
  outcome: CheckInOutcome;
  booking?: BookingDoc;
}

export interface CheckInInput {
  eventId: string;
  qrToken: string;
}

/** Looks up a booking by its scanned/pasted qrToken within one event and, if eligible, checks it
 * in. Mirrors web/src/hooks/useBookings.ts's useCheckIn. */
export function useCheckIn() {
  const invalidate = useInvalidateEventState();

  const mutate = useCallback(async ({ eventId, qrToken }: CheckInInput): Promise<CheckInResult> => {
    const trimmed = qrToken.trim();
    if (!trimmed) return { outcome: "not_found" };

    const res = await mudbaseClient.listDocuments(bookingDocSchema, BOOKINGS_COLLECTION_ID, {
      filter: { eventId, qrToken: trimmed },
      limit: 1,
    });
    const booking = res.data[0];
    if (!booking) return { outcome: "not_found" };
    if (booking.status === "checked_in") return { outcome: "already_checked_in", booking };
    if (booking.status === "cancelled") return { outcome: "cancelled", booking };
    if (booking.status === "waitlisted") return { outcome: "waitlisted", booking };

    const updated = await mudbaseClient.updateDocument(bookingDocSchema, BOOKINGS_COLLECTION_ID, booking._id, {
      status: "checked_in",
    });
    await mudbaseClient.createDocument(activityEntrySchema, ACTIVITY_COLLECTION_ID, {
      eventId,
      actorId: booking.userId,
      actorName: booking.userName,
      action: "checked_in",
    });
    return { outcome: "checked_in", booking: updated };
  }, []);

  return useMutation({
    mutationFn: mutate,
    onSuccess: (result, { eventId }) => {
      if (result.outcome === "checked_in") invalidate(eventId);
    },
  });
}
