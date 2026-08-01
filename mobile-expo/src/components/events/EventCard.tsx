import { Pressable, Text, View } from "react-native";
import { router } from "expo-router";
import { CalendarDays, MapPin } from "lucide-react-native";
import { Card } from "@/components/ui/Card";
import { CapacityBadge } from "@/components/events/CapacityBadge";
import { useConfirmedCount } from "@/hooks/useEvents";
import { formatDateTime } from "@/lib/format";
import type { EventDoc } from "@/api/schemas";

/** Mirrors web/src/components/events/EventCard.tsx. */
export function EventCard({ event }: { event: EventDoc }): React.JSX.Element {
  const { data: confirmed, isLoading } = useConfirmedCount(event._id);

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Open ${event.title}`}
      onPress={() => router.push(`/events/${event._id}`)}
      className="active:opacity-80"
    >
      <Card>
        <View className="flex-row items-start justify-between gap-3">
          <View className="flex-1 gap-1">
            <Text className="text-base font-semibold text-foreground">{event.title}</Text>
            <Text className="text-xs text-muted-foreground">Hosted by {event.organizerName}</Text>
          </View>
          <CapacityBadge confirmed={confirmed} capacity={event.capacity} isLoading={isLoading} />
        </View>
        <View className="mt-3 gap-1.5">
          <View className="flex-row items-center gap-2">
            <CalendarDays size={14} color="#606876" />
            <Text className="text-sm text-muted-foreground">{formatDateTime(event.startsAt)}</Text>
          </View>
          <View className="flex-row items-center gap-2">
            <MapPin size={14} color="#606876" />
            <Text className="text-sm text-muted-foreground">{event.location}</Text>
          </View>
        </View>
      </Card>
    </Pressable>
  );
}
