import { useState } from "react";
import { ActivityIndicator, ScrollView, Text, View } from "react-native";
import { CalendarX, ChevronLeft, ChevronRight } from "lucide-react-native";
import { EventCard } from "@/components/events/EventCard";
import { Button } from "@/components/ui/Button";
import { useEvents } from "@/hooks/useEvents";

/**
 * The events tab's list content, page-button pagination rather than infinite scroll - mirrors
 * web/src/components/events/EventList.tsx's Previous/Next control exactly (this app's "no
 * drag-and-drop, use buttons/pickers" convention extends to pagination too: explicit Previous/Next
 * buttons, not a swipe gesture).
 */
export function EventListScreen(): React.JSX.Element {
  const [page, setPage] = useState(1);
  const { data, isLoading, isError } = useEvents(page);

  if (isLoading) {
    return (
      <View className="flex-1 items-center justify-center py-16">
        <ActivityIndicator size="large" color="#4a43db" />
      </View>
    );
  }

  if (isError) {
    return (
      <View className="flex-1 items-center justify-center px-6 py-16">
        <Text className="text-center text-sm text-destructive">Couldn&apos;t load events. Please sign in and try again.</Text>
      </View>
    );
  }

  const events = data?.data ?? [];

  if (events.length === 0) {
    return (
      <View className="flex-1 items-center justify-center gap-2 py-16">
        <CalendarX size={28} color="#606876" />
        <Text className="text-sm text-muted-foreground">No events yet.</Text>
      </View>
    );
  }

  return (
    <ScrollView contentContainerClassName="gap-3 px-4 pb-8">
      {events.map((event) => (
        <EventCard key={event._id} event={event} />
      ))}

      {data && data.pagination.totalPages > 1 && (
        <View className="flex-row items-center justify-center gap-3 pt-2">
          <Button
            variant="outline"
            size="sm"
            disabled={page <= 1}
            icon={<ChevronLeft size={14} color="#181c25" />}
            onPress={() => setPage((p) => p - 1)}
          >
            Previous
          </Button>
          <Text className="text-sm text-muted-foreground">
            Page {data.pagination.page} of {data.pagination.totalPages}
          </Text>
          <Button
            variant="outline"
            size="sm"
            disabled={!data.pagination.hasMore}
            onPress={() => setPage((p) => p + 1)}
          >
            Next
          </Button>
        </View>
      )}
    </ScrollView>
  );
}
