import { useEffect, useState } from "react";
import { ScrollView, Text } from "react-native";
import { router, useLocalSearchParams } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { mudbaseClient } from "@/api/client";
import { activityEntrySchema } from "@/api/schemas";
import { ACTIVITY_COLLECTION_ID } from "@/config/env";
import { useAuth } from "@/hooks/useAuth";
import { useEvent, useUpdateEvent } from "@/hooks/useEvents";
import { EventForm, type EventFormValues } from "@/components/events/EventForm";

/** Organizer-only, owner-only edit form. Mirrors web/src/app/events/[id]/edit/page.tsx. */
export default function EditEventScreen(): React.JSX.Element {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { user, isOrganizer, isInitializing: authLoading } = useAuth();
  const { data: event, isLoading, isError } = useEvent(id);
  const updateEvent = useUpdateEvent();
  const [error, setError] = useState<string | null>(null);

  const isOwner = !!user && !!event && event.organizerId === user.id;

  useEffect(() => {
    if (!authLoading && !isLoading && (!isOrganizer || (event && !isOwner))) {
      router.replace(`/events/${id}`);
    }
  }, [authLoading, isLoading, isOrganizer, isOwner, event, id]);

  const handleSubmit = async (values: EventFormValues): Promise<void> => {
    if (!user || !id) return;
    setError(null);
    try {
      await updateEvent.mutateAsync({
        eventId: id,
        title: values.title,
        description: values.description || undefined,
        startsAt: values.startsAt.toISOString(),
        location: values.location,
        capacity: values.capacity,
      });
      await mudbaseClient.createDocument(activityEntrySchema, ACTIVITY_COLLECTION_ID, {
        eventId: id,
        actorId: user.id,
        actorName: `${user.firstName} ${user.lastName}`.trim(),
        action: "event_updated",
      });
      router.replace(`/events/${id}`);
    } catch {
      setError("Couldn't save these changes. Please try again.");
    }
  };

  if (authLoading || isLoading || !event || isError || !isOwner) {
    return (
      <SafeAreaView className="flex-1 items-center justify-center bg-background">
        <Text className="text-sm text-muted-foreground">Loading…</Text>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["bottom"]}>
      <ScrollView contentContainerClassName="gap-4 p-4" keyboardShouldPersistTaps="handled">
        <Text className="text-xs text-muted-foreground">Changes to capacity are re-checked against existing bookings.</Text>
        <EventForm
          defaultValues={{
            title: event.title,
            description: event.description ?? "",
            startsAt: new Date(event.startsAt),
            location: event.location,
            capacity: event.capacity,
          }}
          onSubmit={handleSubmit}
          submitting={updateEvent.isPending}
          submitLabel="Save changes"
          errorMessage={error}
        />
      </ScrollView>
    </SafeAreaView>
  );
}
