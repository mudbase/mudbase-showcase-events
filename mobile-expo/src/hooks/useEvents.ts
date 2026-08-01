import { useCallback } from "react";
import { useMutation, useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { mudbaseClient } from "@/api/client";
import { eventDocSchema, bookingDocSchema, type EventDoc } from "@/api/schemas";
import { EVENTS_COLLECTION_ID, BOOKINGS_COLLECTION_ID, ACTIVITY_COLLECTION_ID } from "@/config/env";

const EVENTS_PAGE_SIZE = 10;

/** Mirrors web/src/hooks/useEvents.ts's useEvents(page). */
export function useEvents(page: number) {
  return useQuery({
    queryKey: ["collection", EVENTS_COLLECTION_ID, { page }],
    queryFn: () =>
      mudbaseClient.listDocuments(eventDocSchema, EVENTS_COLLECTION_ID, {
        sort: "startsAt",
        page,
        limit: EVENTS_PAGE_SIZE,
      }),
  });
}

export function useEvent(eventId: string | null | undefined) {
  return useQuery({
    queryKey: ["collection", EVENTS_COLLECTION_ID, "doc", eventId],
    queryFn: () => {
      if (!eventId) throw new Error("useEvent called without an eventId");
      return mudbaseClient.getDocument(eventDocSchema, EVENTS_COLLECTION_ID, eventId);
    },
    enabled: !!eventId,
  });
}

export interface CreateEventInput {
  title: string;
  description?: string;
  startsAt: string;
  location: string;
  capacity: number;
  organizerId: string;
  organizerName: string;
}

export function useCreateEvent() {
  const queryClient = useQueryClient();

  const mutate = useCallback(async (input: CreateEventInput): Promise<EventDoc> => {
    const created = await mudbaseClient.createDocument(eventDocSchema, EVENTS_COLLECTION_ID, {
      title: input.title,
      ...(input.description ? { description: input.description } : {}),
      startsAt: input.startsAt,
      location: input.location,
      capacity: input.capacity,
      organizerId: input.organizerId,
      organizerName: input.organizerName,
    });
    return created;
  }, []);

  return useMutation({
    mutationFn: mutate,
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["collection", EVENTS_COLLECTION_ID] }),
  });
}

export interface UpdateEventInput {
  eventId: string;
  title: string;
  description?: string;
  startsAt: string;
  location: string;
  capacity: number;
}

export function useUpdateEvent() {
  const queryClient = useQueryClient();

  const mutate = useCallback(async (input: UpdateEventInput): Promise<EventDoc> => {
    return mudbaseClient.updateDocument(eventDocSchema, EVENTS_COLLECTION_ID, input.eventId, {
      title: input.title,
      description: input.description ?? "",
      startsAt: input.startsAt,
      location: input.location,
      capacity: input.capacity,
    });
  }, []);

  return useMutation({
    mutationFn: mutate,
    onSuccess: (updated) => {
      queryClient.setQueryData(["collection", EVENTS_COLLECTION_ID, "doc", updated._id], updated);
      void queryClient.invalidateQueries({ queryKey: ["collection", EVENTS_COLLECTION_ID] });
    },
  });
}

export function useDeleteEvent() {
  const queryClient = useQueryClient();

  const mutate = useCallback(async (eventId: string): Promise<void> => {
    await mudbaseClient.deleteDocument(EVENTS_COLLECTION_ID, eventId);
  }, []);

  return useMutation({
    mutationFn: mutate,
    onSuccess: (_data, eventId) => {
      queryClient.removeQueries({ queryKey: ["collection", EVENTS_COLLECTION_ID, "doc", eventId] });
      void queryClient.invalidateQueries({ queryKey: ["collection", EVENTS_COLLECTION_ID] });
    },
  });
}

/** The live confirmed-booking count for one event, for the capacity indicator on its card/detail.
 * Mirrors web/src/hooks/useEvents.ts's useConfirmedCount. */
export function useConfirmedCount(eventId: string | null | undefined) {
  return useQuery({
    queryKey: ["confirmedCount", eventId],
    queryFn: async (): Promise<number> => {
      if (!eventId) return 0;
      const res = await mudbaseClient.listDocuments(bookingDocSchema, BOOKINGS_COLLECTION_ID, {
        filter: { eventId, status: "confirmed" },
        limit: 1,
      });
      return res.pagination.total;
    },
    enabled: !!eventId,
  });
}

/**
 * Resolves a set of event ids (e.g. from the current user's bookings) to their full event docs
 * in parallel, for screens like "My bookings" that need to join booking rows against event
 * details without a native join in a generic-CRUD BaaS. Mirrors web/src/hooks/useEvents.ts's
 * useEventsByIds.
 */
export function useEventsByIds(eventIds: string[]): { byId: Map<string, EventDoc>; isLoading: boolean } {
  const uniqueIds = Array.from(new Set(eventIds));

  const results = useQueries({
    queries: uniqueIds.map((id) => ({
      queryKey: ["collection", EVENTS_COLLECTION_ID, "doc", id],
      queryFn: () => mudbaseClient.getDocument(eventDocSchema, EVENTS_COLLECTION_ID, id),
      enabled: !!id,
    })),
  });

  const byId = new Map<string, EventDoc>();
  uniqueIds.forEach((id, index) => {
    const data = results[index]?.data;
    if (data) byId.set(id, data);
  });

  return { byId, isLoading: results.some((r) => r.isLoading) };
}

/** Invalidates every cache entry a booking mutation on this event could have changed. Mirrors
 * web/src/hooks/useEvents.ts's useInvalidateEventState. */
export function useInvalidateEventState() {
  const queryClient = useQueryClient();
  return useCallback(
    (eventId: string) => {
      void queryClient.invalidateQueries({ queryKey: ["confirmedCount", eventId] });
      void queryClient.invalidateQueries({ queryKey: ["collection", BOOKINGS_COLLECTION_ID] });
      void queryClient.invalidateQueries({ queryKey: ["collection", ACTIVITY_COLLECTION_ID] });
    },
    [queryClient],
  );
}
