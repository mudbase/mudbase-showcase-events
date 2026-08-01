"use client"

import { useEffect, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import { useAuth } from "@/hooks/useAuth"
import { useEvent, useUpdateEvent } from "@/hooks/useEvents"
import { useMudbase } from "@/lib/mudbase-provider"
import { ACTIVITY_COLLECTION_ID } from "@/lib/config"
import { EventForm, type EventFormValues } from "@/components/events/EventForm"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { toDateTimeLocalValue } from "@/lib/utils"

export default function EditEventPage(): React.JSX.Element {
  const params = useParams<{ id: string }>()
  const eventId = params.id
  const { user, isOrganizer, loading: authLoading } = useAuth()
  const router = useRouter()
  const { client } = useMudbase()
  const { data: event, isLoading, isError } = useEvent(eventId)
  const updateEvent = useUpdateEvent()
  const [error, setError] = useState<string | null>(null)

  const isOwner = !!user && !!event && event.organizerId === user.id

  useEffect(() => {
    if (!authLoading && !isLoading && (!isOrganizer || (event && !isOwner))) {
      router.replace(`/events/${eventId}`)
    }
  }, [authLoading, isLoading, isOrganizer, isOwner, event, eventId, router])

  const handleSubmit = async (values: EventFormValues): Promise<void> => {
    if (!user) return
    setError(null)
    try {
      await updateEvent.mutateAsync({
        documentId: eventId,
        data: {
          title: values.title,
          description: values.description || undefined,
          startsAt: new Date(values.startsAt).toISOString(),
          location: values.location,
          capacity: values.capacity,
        },
      })
      await client.createDocument(ACTIVITY_COLLECTION_ID, {
        eventId,
        actorId: user.id,
        actorName: `${user.firstName} ${user.lastName}`.trim(),
        action: "event_updated",
      })
      router.push(`/events/${eventId}`)
    } catch {
      setError("Couldn't save these changes. Please try again.")
    }
  }

  if (authLoading || isLoading || !event || isError || !isOwner) {
    return <p className="container py-16 text-center text-sm text-muted-foreground">Loading…</p>
  }

  return (
    <div className="container max-w-lg py-12">
      <Card>
        <CardHeader>
          <CardTitle>Edit event</CardTitle>
          <CardDescription>Changes to capacity are re-checked against existing bookings.</CardDescription>
        </CardHeader>
        <CardContent>
          <EventForm
            defaultValues={{
              title: event.title,
              description: event.description ?? "",
              startsAt: toDateTimeLocalValue(event.startsAt),
              location: event.location,
              capacity: event.capacity,
            }}
            onSubmit={handleSubmit}
            submitting={updateEvent.isPending}
            submitLabel="Save changes"
            errorMessage={error}
          />
        </CardContent>
      </Card>
    </div>
  )
}
