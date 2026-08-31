import { useEffect, useState } from "react";
import { ScrollView, Text } from "react-native";
import { router } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { mudbaseClient } from "@/api/client";
import { activityEntrySchema } from "@/api/schemas";
import { ACTIVITY_COLLECTION_ID } from "@/config/env";
import { useAuth } from "@/hooks/useAuth";
import { useCreateEvent } from "@/hooks/useEvents";
import { EventForm, type EventFormValues } from "@/components/events/EventForm";

/** Organizer-only create form. Mirrors web/src/app/events/new/page.tsx. */
export default function NewEventScreen(): React.JSX.Element {
  const { user, isOrganizer, isInitializing } = useAuth();
  const createEvent = useCreateEvent();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isInitializing && !isOrganizer) router.back();
  }, [isInitializing, isOrganizer]);

  const handleSubmit = async (values: EventFormValues): Promise<void> => {
    if (!user) return;
    setError(null);
    try {
      const created = await createEvent.mutateAsync({
        title: values.title,
        description: values.description || undefined,
        startsAt: values.startsAt.toISOString(),
        location: values.location,
        capacity: values.capacity,
        organizerId: user.id,
        organizerName: `${user.firstName} ${user.lastName}`.trim(),
      });
      await mudbaseClient.createDocument(activityEntrySchema, ACTIVITY_COLLECTION_ID, {
        eventId: created._id,
        actorId: user.id,
        actorName: `${user.firstName} ${user.lastName}`.trim(),
        action: "event_created",
      });
      router.replace(`/events/${created._id}`);
    } catch {
      setError("Couldn't create this event. Please try again.");
    }
  };

  if (isInitializing || !isOrganizer) {
    return (
      <SafeAreaView className="flex-1 items-center justify-center bg-background">
        <Text className="text-sm text-muted-foreground">Loading…</Text>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["bottom"]}>
      <ScrollView contentContainerClassName="gap-4 p-4" keyboardShouldPersistTaps="handled">
        <Text className="text-xs text-muted-foreground">
          Set a capacity - bookings beyond it are automatically waitlisted.
        </Text>
        <EventForm
          onSubmit={handleSubmit}
          submitting={createEvent.isPending}
          submitLabel="Create event"
          errorMessage={error}
        />
      </ScrollView>
    </SafeAreaView>
  );
}
