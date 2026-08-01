"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { Pencil, QrCode, Trash2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { useDeleteEvent } from "@/hooks/useEvents"

export function OrganizerActions({ eventId }: { eventId: string }): React.JSX.Element {
  const router = useRouter()
  const deleteEvent = useDeleteEvent()
  const [confirming, setConfirming] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleDelete = async (): Promise<void> => {
    setError(null)
    try {
      await deleteEvent.mutateAsync(eventId)
      router.push("/")
    } catch {
      setError("Couldn't delete this event. Please try again.")
      setConfirming(false)
    }
  }

  return (
    <div className="flex flex-wrap items-center gap-2 rounded-md border border-border bg-secondary/40 p-3">
      <span className="mr-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">Organizer</span>
      <Button asChild variant="outline" size="sm">
        <Link href={`/events/${eventId}/edit`}>
          <Pencil className="mr-2 h-4 w-4" />
          Edit
        </Link>
      </Button>
      <Button asChild variant="outline" size="sm">
        <Link href={`/events/${eventId}/checkin`}>
          <QrCode className="mr-2 h-4 w-4" />
          Check-in
        </Link>
      </Button>

      {confirming ? (
        <div className="flex items-center gap-2">
          <span className="text-sm text-muted-foreground">Delete this event permanently?</span>
          <Button variant="destructive" size="sm" onClick={() => void handleDelete()} disabled={deleteEvent.isPending}>
            {deleteEvent.isPending ? "Deleting…" : "Confirm delete"}
          </Button>
          <Button variant="ghost" size="sm" onClick={() => setConfirming(false)}>
            Cancel
          </Button>
        </div>
      ) : (
        <Button variant="destructive" size="sm" onClick={() => setConfirming(true)}>
          <Trash2 className="mr-2 h-4 w-4" />
          Delete
        </Button>
      )}

      {error && <p className="w-full text-sm text-destructive">{error}</p>}
    </div>
  )
}
