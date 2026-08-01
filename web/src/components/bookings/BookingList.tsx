"use client"

import { useState } from "react"
import { Ticket } from "lucide-react"
import { useAuth } from "@/hooks/useAuth"
import { useMyBookings, useCancelBooking } from "@/hooks/useBookings"
import { useEventsByIds } from "@/hooks/useEvents"
import { BookingCard } from "@/components/bookings/BookingCard"
import type { BookingDoc } from "@/types/booking"

export function BookingList(): React.JSX.Element {
  const { user } = useAuth()
  const { data, isLoading } = useMyBookings(user?.id)
  const bookings = data?.data ?? []
  const { byId: eventsById } = useEventsByIds(bookings.map((b) => b.eventId))
  const cancelBooking = useCancelBooking()
  const [cancellingId, setCancellingId] = useState<string | null>(null)

  const handleCancel = async (booking: BookingDoc): Promise<void> => {
    const event = eventsById.get(booking.eventId)
    if (!event || !user) return
    setCancellingId(booking._id)
    try {
      await cancelBooking.mutateAsync({
        bookingId: booking._id,
        eventId: booking.eventId,
        capacity: event.capacity,
        userId: user.id,
        userName: `${user.firstName} ${user.lastName}`.trim(),
      })
    } finally {
      setCancellingId(null)
    }
  }

  if (isLoading) {
    return <p className="py-12 text-center text-sm text-muted-foreground">Loading your bookings…</p>
  }

  if (bookings.length === 0) {
    return (
      <div className="flex flex-col items-center gap-2 py-16 text-center text-muted-foreground">
        <Ticket className="h-8 w-8" aria-hidden />
        <p className="text-sm">You haven&apos;t booked any events yet.</p>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {bookings.map((booking) => (
        <BookingCard
          key={booking._id}
          booking={booking}
          event={eventsById.get(booking.eventId)}
          onCancel={(b) => void handleCancel(b)}
          cancelling={cancellingId === booking._id}
        />
      ))}
    </div>
  )
}
