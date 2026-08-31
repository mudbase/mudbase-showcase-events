"use client"

import { useState } from "react"
import Link from "next/link"
import { useAuth } from "@/hooks/useAuth"
import { useCreateBooking, useMyBookingForEvent } from "@/hooks/useBookings"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import type { EventDoc } from "@/types/event"

const STATUS_LABEL: Record<string, string> = {
  confirmed: "You're booked",
  waitlisted: "You're on the waitlist",
  checked_in: "You're checked in",
  cancelled: "Booking cancelled",
}

export function BookButton({ event }: { event: EventDoc }): React.JSX.Element | null {
  const { user, isAuthenticated } = useAuth()
  const [feedback, setFeedback] = useState<string | null>(null)
  const { data: existing, isLoading: existingLoading } = useMyBookingForEvent(event._id, user?.id)
  const createBooking = useCreateBooking()

  const isOwnEvent = !!user && event.organizerId === user.id
  if (isOwnEvent) return null

  if (!isAuthenticated || !user) {
    return (
      <Button asChild>
        <Link href="/login">Sign in to book</Link>
      </Button>
    )
  }

  if (existingLoading) {
    return (
      <Button disabled variant="outline">
        Checking your booking…
      </Button>
    )
  }

  const activeBooking = existing?.data.find((b) => b.status !== "cancelled")
  if (activeBooking) {
    return (
      <div className="flex items-center gap-2">
        <Badge variant={activeBooking.status === "waitlisted" ? "warning" : "success"}>
          {STATUS_LABEL[activeBooking.status]}
        </Badge>
        <Button asChild variant="outline" size="sm">
          <Link href="/bookings">View my bookings</Link>
        </Button>
      </div>
    )
  }

  const handleBook = async (): Promise<void> => {
    setFeedback(null)
    try {
      const booking = await createBooking.mutateAsync({
        eventId: event._id,
        capacity: event.capacity,
        userId: user.id,
        userName: `${user.firstName} ${user.lastName}`.trim(),
      })
      setFeedback(
        booking.status === "confirmed"
          ? "You're confirmed! See your ticket under My bookings."
          : "This event is full - you've been added to the waitlist.",
      )
    } catch {
      setFeedback("Couldn't complete your booking. Please try again.")
    }
  }

  return (
    <div className="space-y-2">
      <Button onClick={() => void handleBook()} disabled={createBooking.isPending}>
        {createBooking.isPending ? "Booking…" : "Book this event"}
      </Button>
      {feedback && <p className="text-sm text-muted-foreground">{feedback}</p>}
    </div>
  )
}
