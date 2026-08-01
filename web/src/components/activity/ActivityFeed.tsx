"use client"

import { Activity } from "lucide-react"
import { useEventActivity } from "@/hooks/useActivity"
import { formatRelativeTime } from "@/lib/utils"
import { ACTIVITY_LABELS } from "@/types/activity"

export function ActivityFeed({ eventId }: { eventId: string }): React.JSX.Element {
  const { data, isLoading } = useEventActivity(eventId)
  const entries = data?.data ?? []

  return (
    <div className="space-y-3">
      <h2 className="flex items-center gap-2 text-sm font-semibold text-foreground">
        <Activity className="h-4 w-4" aria-hidden />
        Activity
      </h2>

      {isLoading && <p className="text-sm text-muted-foreground">Loading activity…</p>}

      {!isLoading && entries.length === 0 && <p className="text-sm text-muted-foreground">No activity yet.</p>}

      <ul className="space-y-2">
        {entries.map((entry) => (
          <li key={entry._id} className="flex items-baseline justify-between gap-3 text-sm">
            <span>
              <span className="font-medium">{entry.actorName}</span>{" "}
              <span className="text-muted-foreground">{ACTIVITY_LABELS[entry.action]}</span>
            </span>
            <span className="shrink-0 text-xs text-muted-foreground">{formatRelativeTime(entry.createdAt)}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}
