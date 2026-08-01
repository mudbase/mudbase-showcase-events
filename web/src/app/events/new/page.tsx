"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { useAuth } from "@/hooks/useAuth"
import { useCreateEvent } from "@/hooks/useEvents"
import { useMudbase } from "@/lib/mudbase-provider"
import { ACTIVITY_COLLECTION_ID } from "@/lib/config"
import { EventForm, type EventFormValues } from "@/components/events/EventForm"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"

export default function NewEventPage(): React.JSX.Element {
  const { user, isOrganizer, loading } = useAuth()
  const router = useRouter()
  const { client } = useMudbase()
  const createEvent = useCreateEvent()
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!loading && !isOrganizer) router.replace("/")
  }, [loading, isOrganizer, router])

  const handleSubmit = async (values: EventFormValues): Promise<void> => {
    if (!user) return
    setError(null)
    try {
      const created = await createEvent.mutateAsync({
        title: values.title,
        description: values.description || undefined,
        startsAt: new Date(values.startsAt).toISOString(),
        location: values.location,
        capacity: values.capacity,
        organizerId: user.id,
        organizerName: `${user.firstName} ${user.lastName}`.trim(),
      })
      await client.createDocument(ACTIVITY_COLLECTION_ID, {
        eventId: created._id,
        actorId: user.id,
        actorName: `${user.firstName} ${user.lastName}`.trim(),
        action: "event_created",
      })
      router.push(`/events/${created._id}`)
    } catch {
      setError("Couldn't create this event. Please try again.")
    }
  }

  if (loading || !isOrganizer) {
    return <p className="container py-16 text-center text-sm text-muted-foreground">Loading…</p>
  }

  return (
    <div className="container max-w-lg py-12">
      <Card>
        <CardHeader>
          <CardTitle>New event</CardTitle>
          <CardDescription>Set a capacity — bookings beyond it are automatically waitlisted.</CardDescription>
        </CardHeader>
        <CardContent>
          <EventForm
            onSubmit={handleSubmit}
            submitting={createEvent.isPending}
            submitLabel="Create event"
            errorMessage={error}
          />
        </CardContent>
      </Card>
    </div>
  )
}
