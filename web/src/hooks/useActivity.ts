"use client"

import { ACTIVITY_COLLECTION_ID } from "@/lib/config"
import { useDocuments } from "@/hooks/useCollection"
import type { ActivityDoc } from "@/types/activity"

/** Reverse-chronological activity feed for one event: booking created, cancelled, promoted, checked in. */
export function useEventActivity(eventId: string | null | undefined) {
  return useDocuments<ActivityDoc>(
    ACTIVITY_COLLECTION_ID,
    { filter: { eventId: eventId ?? "" }, sort: "-createdAt", limit: 50 },
    { enabled: !!eventId },
  )
}
