import { useEffect } from "react";
import { ScrollView, Text } from "react-native";
import { router, useLocalSearchParams } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { useAuth } from "@/hooks/useAuth";
import { useEvent } from "@/hooks/useEvents";
import { CheckInForm } from "@/components/bookings/CheckInForm";

/** Organizer-only, owner-only manual QR-token check-in. Mirrors web/src/app/events/[id]/checkin/page.tsx. */
export default function CheckInScreen(): React.JSX.Element {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { user, isOrganizer, isInitializing: authLoading } = useAuth();
  const { data: event, isLoading, isError } = useEvent(id);

  const isOwner = !!user && !!event && event.organizerId === user.id;

  useEffect(() => {
    if (!authLoading && !isLoading && (!isOrganizer || (event && !isOwner))) {
      router.replace(`/events/${id}`);
    }
  }, [authLoading, isLoading, isOrganizer, isOwner, event, id]);

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
        <Text className="text-lg font-semibold text-foreground">{event.title}</Text>
        <Text className="text-xs text-muted-foreground">Paste or type the guest&apos;s scanned QR code to check them in.</Text>
        <CheckInForm eventId={event._id} />
      </ScrollView>
    </SafeAreaView>
  );
}
