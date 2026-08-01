"use client"

import { useParams } from "next/navigation"
import { CalendarDays, MapPin, Users } from "lucide-react"
import { useAuth } from "@/hooks/useAuth"
import { useEvent, useConfirmedCount } from "@/hooks/useEvents"
import { CapacityBadge } from "@/components/events/CapacityBadge"
import { BookButton } from "@/components/events/BookButton"
import { OrganizerActions } from "@/components/events/OrganizerActions"
import { ActivityFeed } from "@/components/activity/ActivityFeed"
import { Separator } from "@/components/ui/separator"
import { formatDateTime } from "@/lib/utils"

export default function EventDetailPage(): React.JSX.Element {
  const params = useParams<{ id: string }>()
  const eventId = params.id
  const { user } = useAuth()
  const { data: event, isLoading, isError } = useEvent(eventId)
  const { data: confirmed, isLoading: confirmedLoading } = useConfirmedCount(eventId)

  if (isLoading) {
    return <p className="container py-16 text-center text-sm text-muted-foreground">Loading event…</p>
  }

  if (isError || !event) {
    return <p className="container py-16 text-center text-sm text-muted-foreground">Event not found.</p>
  }

  const isOwner = !!user && event.organizerId === user.id

  return (
    <div className="container max-w-2xl space-y-6 py-8">
      <div className="space-y-3">
        <div className="flex items-start justify-between gap-4">
          <h1 className="text-2xl font-semibold tracking-tight">{event.title}</h1>
          <CapacityBadge confirmed={confirmed} capacity={event.capacity} isLoading={confirmedLoading} />
        </div>
        <p className="text-sm text-muted-foreground">Hosted by {event.organizerName}</p>

        <div className="space-y-1.5 text-sm text-muted-foreground">
          <div className="flex items-center gap-2">
            <CalendarDays className="h-4 w-4 shrink-0" aria-hidden />
            {formatDateTime(event.startsAt)}
          </div>
          <div className="flex items-center gap-2">
            <MapPin className="h-4 w-4 shrink-0" aria-hidden />
            {event.location}
          </div>
          <div className="flex items-center gap-2">
            <Users className="h-4 w-4 shrink-0" aria-hidden />
            Capacity: {event.capacity}
          </div>
        </div>

        {event.description && <p className="whitespace-pre-wrap pt-2 text-sm leading-relaxed">{event.description}</p>}
      </div>

      <BookButton event={event} />

      {isOwner && <OrganizerActions eventId={event._id} />}

      <Separator />

      <ActivityFeed eventId={event._id} />
    </div>
  )
}
