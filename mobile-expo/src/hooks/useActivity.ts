import { useQuery } from "@tanstack/react-query";
import { mudbaseClient } from "@/api/client";
import { activityEntrySchema } from "@/api/schemas";
import { ACTIVITY_COLLECTION_ID } from "@/config/env";

/** Reverse-chronological activity feed for one event: booking created, cancelled, promoted,
 * checked in. Mirrors web/src/hooks/useActivity.ts's useEventActivity. */
export function useEventActivity(eventId: string | null | undefined) {
  return useQuery({
    queryKey: ["collection", ACTIVITY_COLLECTION_ID, { eventId }],
    queryFn: () =>
      mudbaseClient.listDocuments(activityEntrySchema, ACTIVITY_COLLECTION_ID, {
        filter: { eventId: eventId ?? "" },
        sort: "-createdAt",
        limit: 50,
      }),
    enabled: !!eventId,
  });
}
