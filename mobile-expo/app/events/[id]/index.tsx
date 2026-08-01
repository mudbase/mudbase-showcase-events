import { ActivityIndicator, ScrollView, Text, View } from "react-native";
import { useLocalSearchParams } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { CalendarDays, MapPin, Users } from "lucide-react-native";
import { useAuth } from "@/hooks/useAuth";
import { useEvent, useConfirmedCount } from "@/hooks/useEvents";
import { CapacityBadge } from "@/components/events/CapacityBadge";
import { BookButton } from "@/components/events/BookButton";
import { OrganizerActions } from "@/components/events/OrganizerActions";
import { ActivityFeed } from "@/components/activity/ActivityFeed";
import { Separator } from "@/components/ui/Separator";
import { formatDateTime } from "@/lib/format";

/** Mirrors web/src/app/events/[id]/page.tsx. */
export default function EventDetailScreen(): React.JSX.Element {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { user } = useAuth();
  const { data: event, isLoading, isError } = useEvent(id);
  const { data: confirmed, isLoading: confirmedLoading } = useConfirmedCount(id);

  if (isLoading) {
    return (
      <SafeAreaView className="flex-1 items-center justify-center bg-background">
        <ActivityIndicator size="large" color="#4a43db" />
      </SafeAreaView>
    );
  }

  if (isError || !event) {
    return (
      <SafeAreaView className="flex-1 items-center justify-center bg-background px-6">
        <Text className="text-center text-sm text-muted-foreground">Event not found.</Text>
      </SafeAreaView>
    );
  }

  const isOwner = !!user && event.organizerId === user.id;

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["bottom"]}>
      <ScrollView contentContainerClassName="gap-4 p-4">
        <View className="gap-2">
          <View className="flex-row items-start justify-between gap-3">
            <Text className="flex-1 text-2xl font-semibold text-foreground">{event.title}</Text>
            <CapacityBadge confirmed={confirmed} capacity={event.capacity} isLoading={confirmedLoading} />
          </View>
          <Text className="text-sm text-muted-foreground">Hosted by {event.organizerName}</Text>

          <View className="gap-1.5">
            <View className="flex-row items-center gap-2">
              <CalendarDays size={15} color="#606876" />
              <Text className="text-sm text-muted-foreground">{formatDateTime(event.startsAt)}</Text>
            </View>
            <View className="flex-row items-center gap-2">
              <MapPin size={15} color="#606876" />
              <Text className="text-sm text-muted-foreground">{event.location}</Text>
            </View>
            <View className="flex-row items-center gap-2">
              <Users size={15} color="#606876" />
              <Text className="text-sm text-muted-foreground">Capacity: {event.capacity}</Text>
            </View>
          </View>

          {event.description && <Text className="pt-2 text-sm leading-relaxed text-foreground">{event.description}</Text>}
        </View>

        <BookButton event={event} />

        {isOwner && <OrganizerActions eventId={event._id} />}

        <Separator />

        <ActivityFeed eventId={event._id} />
      </ScrollView>
    </SafeAreaView>
  );
}
