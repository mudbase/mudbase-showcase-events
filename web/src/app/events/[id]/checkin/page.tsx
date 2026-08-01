"use client"

import { useEffect } from "react"
import { useParams, useRouter } from "next/navigation"
import { useAuth } from "@/hooks/useAuth"
import { useEvent } from "@/hooks/useEvents"
import { CheckInForm } from "@/components/bookings/CheckInForm"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"

export default function CheckInPage(): React.JSX.Element {
  const params = useParams<{ id: string }>()
  const eventId = params.id
  const { user, isOrganizer, loading: authLoading } = useAuth()
  const router = useRouter()
  const { data: event, isLoading, isError } = useEvent(eventId)

  const isOwner = !!user && !!event && event.organizerId === user.id

  useEffect(() => {
    if (!authLoading && !isLoading && (!isOrganizer || (event && !isOwner))) {
      router.replace(`/events/${eventId}`)
    }
  }, [authLoading, isLoading, isOrganizer, isOwner, event, eventId, router])

  if (authLoading || isLoading || !event || isError || !isOwner) {
    return <p className="container py-16 text-center text-sm text-muted-foreground">Loading…</p>
  }

  return (
    <div className="container max-w-lg py-12">
      <Card>
        <CardHeader>
          <CardTitle>Check in — {event.title}</CardTitle>
          <CardDescription>Paste or type the guest&apos;s scanned QR code to check them in.</CardDescription>
        </CardHeader>
        <CardContent>
          <CheckInForm eventId={event._id} />
        </CardContent>
      </Card>
    </div>
  )
}
