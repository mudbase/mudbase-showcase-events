"use client"

import Link from "next/link"
import { QRCodeSVG } from "qrcode.react"
import { CalendarDays, MapPin } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { formatDateTime } from "@/lib/utils"
import type { BookingDoc } from "@/types/booking"
import type { EventDoc } from "@/types/event"

const STATUS_VARIANT: Record<BookingDoc["status"], "success" | "warning" | "secondary" | "outline"> = {
  confirmed: "success",
  waitlisted: "warning",
  checked_in: "secondary",
  cancelled: "outline",
}

const STATUS_LABEL: Record<BookingDoc["status"], string> = {
  confirmed: "Confirmed",
  waitlisted: "Waitlisted",
  checked_in: "Checked in",
  cancelled: "Cancelled",
}

export function BookingCard({
  booking,
  event,
  onCancel,
  cancelling,
}: {
  booking: BookingDoc
  event: EventDoc | undefined
  onCancel: (booking: BookingDoc) => void
  cancelling: boolean
}): React.JSX.Element {
  const canCancel = booking.status === "confirmed" || booking.status === "waitlisted"

  return (
    <Card>
      <CardHeader className="flex-row items-start justify-between space-y-0 pb-3">
        <div className="space-y-1">
          <CardTitle>
            {event ? <Link href={`/events/${event._id}`}>{event.title}</Link> : "Event unavailable"}
          </CardTitle>
          {event && (
            <div className="space-y-1 text-xs text-muted-foreground">
              <div className="flex items-center gap-1.5">
                <CalendarDays className="h-3.5 w-3.5" aria-hidden />
                {formatDateTime(event.startsAt)}
              </div>
              <div className="flex items-center gap-1.5">
                <MapPin className="h-3.5 w-3.5" aria-hidden />
                {event.location}
              </div>
            </div>
          )}
        </div>
        <Badge variant={STATUS_VARIANT[booking.status]}>{STATUS_LABEL[booking.status]}</Badge>
      </CardHeader>
      <CardContent className="flex items-center justify-between gap-4 pt-0">
        {booking.status !== "cancelled" ? (
          <div className="flex items-center gap-3">
            <div className="rounded-md border border-border bg-white p-2">
              <QRCodeSVG value={booking.qrToken} size={72} />
            </div>
            <p className="max-w-[16rem] break-all font-mono text-xs text-muted-foreground">{booking.qrToken}</p>
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">This booking was cancelled.</p>
        )}

        {canCancel && (
          <Button variant="outline" size="sm" onClick={() => onCancel(booking)} disabled={cancelling}>
            {cancelling ? "Cancelling…" : "Cancel"}
          </Button>
        )}
      </CardContent>
    </Card>
  )
}
