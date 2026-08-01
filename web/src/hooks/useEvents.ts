"use client"

import { useQuery, useQueries, useQueryClient, type UseQueryOptions } from "@tanstack/react-query"
import { EVENTS_COLLECTION_ID, BOOKINGS_COLLECTION_ID, ACTIVITY_COLLECTION_ID } from "@/lib/config"
import { useMudbase } from "@/lib/mudbase-provider"
import {
  useDocuments,
  useDocument,
  useCreateDocument,
  useUpdateDocument,
  useDeleteDocument,
} from "@/hooks/useCollection"
import type { ListResponse } from "@/lib/mudbase"
import type { EventDoc } from "@/types/event"
import type { BookingDoc } from "@/types/booking"

const EVENTS_PAGE_SIZE = 10

export function useEvents(page: number) {
  return useDocuments<EventDoc>(EVENTS_COLLECTION_ID, { sort: "startsAt", page, limit: EVENTS_PAGE_SIZE })
}

export function useEvent(eventId: string | null | undefined) {
  return useDocument<EventDoc>(EVENTS_COLLECTION_ID, eventId)
}

export function useCreateEvent() {
  return useCreateDocument<EventDoc>(EVENTS_COLLECTION_ID)
}

export function useUpdateEvent() {
  return useUpdateDocument<EventDoc>(EVENTS_COLLECTION_ID)
}

export function useDeleteEvent() {
  return useDeleteDocument(EVENTS_COLLECTION_ID)
}

/** The live confirmed-booking count for one event, for the capacity indicator on its card/detail. */
export function useConfirmedCount(
  eventId: string,
  options?: Omit<UseQueryOptions<number>, "queryKey" | "queryFn">,
) {
  const { client, session } = useMudbase()
  return useQuery<number>({
    queryKey: ["confirmedCount", eventId],
    queryFn: async () => {
      const res: ListResponse<BookingDoc> = await client.getDocuments<BookingDoc>(BOOKINGS_COLLECTION_ID, {
        filter: { eventId, status: "confirmed" },
        limit: 1,
      })
      return res.pagination.total
    },
    enabled: !!session && !!eventId,
    ...options,
  })
}

/**
 * Resolves a set of event ids (e.g. from the current user's bookings) to their full event docs
 * in parallel, for pages like `/bookings` that need to join booking rows against event details
 * without a native join in a generic-CRUD BaaS.
 */
export function useEventsByIds(eventIds: string[]): { byId: Map<string, EventDoc>; isLoading: boolean } {
  const { client, session } = useMudbase()
  const uniqueIds = Array.from(new Set(eventIds))

  const results = useQueries({
    queries: uniqueIds.map((id) => ({
      queryKey: ["collection", EVENTS_COLLECTION_ID, "doc", id],
      queryFn: () => client.getDocument<EventDoc>(EVENTS_COLLECTION_ID, id),
      enabled: !!session && !!id,
    })),
  })

  const byId = new Map<string, EventDoc>()
  uniqueIds.forEach((id, index) => {
    const data = results[index]?.data
    if (data) byId.set(id, data)
  })

  return { byId, isLoading: results.some((r) => r.isLoading) }
}

/** Invalidates every cache entry a booking mutation on this event could have changed. */
export function useInvalidateEventState() {
  const queryClient = useQueryClient()
  return (eventId: string) => {
    void queryClient.invalidateQueries({ queryKey: ["confirmedCount", eventId] })
    void queryClient.invalidateQueries({ queryKey: ["collection", BOOKINGS_COLLECTION_ID] })
    void queryClient.invalidateQueries({ queryKey: ["collection", ACTIVITY_COLLECTION_ID] })
  }
}
