import Link from "next/link"
import { CalendarDays, MapPin } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { CapacityBadge } from "@/components/events/CapacityBadge"
import { useConfirmedCount } from "@/hooks/useEvents"
import { formatDateTime } from "@/lib/utils"
import type { EventDoc } from "@/types/event"

export function EventCard({ event }: { event: EventDoc }): React.JSX.Element {
  const { data: confirmed, isLoading } = useConfirmedCount(event._id)

  return (
    <Link href={`/events/${event._id}`}>
      <Card className="transition-colors hover:border-primary/50 hover:bg-accent/5">
        <CardHeader className="flex-row items-start justify-between space-y-0 pb-3">
          <div className="space-y-1">
            <CardTitle>{event.title}</CardTitle>
            <p className="text-xs text-muted-foreground">Hosted by {event.organizerName}</p>
          </div>
          <CapacityBadge confirmed={confirmed} capacity={event.capacity} isLoading={isLoading} />
        </CardHeader>
        <CardContent className="space-y-2 pt-0 text-sm text-muted-foreground">
          <div className="flex items-center gap-2">
            <CalendarDays className="h-4 w-4 shrink-0" aria-hidden />
            {formatDateTime(event.startsAt)}
          </div>
          <div className="flex items-center gap-2">
            <MapPin className="h-4 w-4 shrink-0" aria-hidden />
            {event.location}
          </div>
        </CardContent>
      </Card>
    </Link>
  )
}
