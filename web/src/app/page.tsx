"use client"

import Link from "next/link"
import { EventList } from "@/components/events/EventList"
import { Button } from "@/components/ui/button"
import { useAuth } from "@/hooks/useAuth"

export default function HomePage(): React.JSX.Element {
  const { isAuthenticated, isOrganizer, loading } = useAuth()

  if (!loading && !isAuthenticated) {
    return (
      <div className="container flex max-w-md flex-col items-center gap-4 py-24 text-center">
        <h1 className="text-2xl font-semibold tracking-tight">Sign in to see upcoming events</h1>
        <p className="text-sm text-muted-foreground">
          Events, bookings, and check-in are all gated behind your organizer or attendee account.
        </p>
        <div className="flex gap-2">
          <Button asChild>
            <Link href="/login">Sign in</Link>
          </Button>
          <Button asChild variant="outline">
            <Link href="/register">Create an account</Link>
          </Button>
        </div>
      </div>
    )
  }

  return (
    <div className="container max-w-4xl space-y-6 py-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Upcoming events</h1>
          <p className="text-sm text-muted-foreground">Sorted soonest first.</p>
        </div>
        {isOrganizer && (
          <Button asChild>
            <Link href="/events/new">New event</Link>
          </Button>
        )}
      </div>
      <EventList />
    </div>
  )
}
