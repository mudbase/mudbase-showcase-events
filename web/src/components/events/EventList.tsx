"use client"

import { useState } from "react"
import { ChevronLeft, ChevronRight, CalendarX } from "lucide-react"
import { EventCard } from "@/components/events/EventCard"
import { Button } from "@/components/ui/button"
import { useEvents } from "@/hooks/useEvents"

export function EventList(): React.JSX.Element {
  const [page, setPage] = useState(1)
  const { data, isLoading, isError } = useEvents(page)

  if (isLoading) {
    return <p className="py-12 text-center text-sm text-muted-foreground">Loading events…</p>
  }

  if (isError) {
    return (
      <p className="py-12 text-center text-sm text-muted-foreground">
        Couldn&apos;t load events. Please sign in and try again.
      </p>
    )
  }

  const events = data?.data ?? []

  if (events.length === 0) {
    return (
      <div className="flex flex-col items-center gap-2 py-16 text-center text-muted-foreground">
        <CalendarX className="h-8 w-8" aria-hidden />
        <p className="text-sm">No events yet.</p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="grid gap-4 sm:grid-cols-2">
        {events.map((event) => (
          <EventCard key={event._id} event={event} />
        ))}
      </div>

      {data && data.pagination.totalPages > 1 && (
        <div className="flex items-center justify-center gap-3">
          <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
            <ChevronLeft className="mr-1 h-4 w-4" />
            Previous
          </Button>
          <span className="text-sm text-muted-foreground">
            Page {data.pagination.page} of {data.pagination.totalPages}
          </span>
          <Button variant="outline" size="sm" disabled={!data.pagination.hasMore} onClick={() => setPage((p) => p + 1)}>
            Next
            <ChevronRight className="ml-1 h-4 w-4" />
          </Button>
        </div>
      )}
    </div>
  )
}
