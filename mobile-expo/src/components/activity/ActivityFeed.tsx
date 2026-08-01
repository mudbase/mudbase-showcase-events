import { ActivityIndicator, Text, View } from "react-native";
import { Activity } from "lucide-react-native";
import { useEventActivity } from "@/hooks/useActivity";
import { formatRelativeTime } from "@/lib/format";
import { ACTIVITY_LABELS } from "@/api/schemas";

/** Per-event activity feed. Demo scale (a handful of bookings/actions per event, capped at 50
 * server-side) — a plain `.map()`, matching web/src/components/activity/ActivityFeed.tsx's own
 * choice not to virtualize at this scale (see plan/build-plan.md). */
export function ActivityFeed({ eventId }: { eventId: string }): React.JSX.Element {
  const { data, isLoading } = useEventActivity(eventId);
  const entries = data?.data ?? [];

  return (
    <View className="gap-3">
      <View className="flex-row items-center gap-2">
        <Activity size={16} color="#181c25" />
        <Text className="text-sm font-semibold text-foreground">Activity</Text>
      </View>

      {isLoading && (
        <View className="items-center py-4">
          <ActivityIndicator color="#4a43db" />
        </View>
      )}

      {!isLoading && entries.length === 0 && <Text className="text-sm text-muted-foreground">No activity yet.</Text>}

      <View className="gap-2">
        {entries.map((entry) => (
          <View key={entry._id} className="flex-row items-baseline justify-between gap-3">
            <Text className="flex-1 text-sm text-foreground">
              <Text className="font-medium">{entry.actorName}</Text>{" "}
              <Text className="text-muted-foreground">{ACTIVITY_LABELS[entry.action]}</Text>
            </Text>
            <Text className="shrink-0 text-xs text-muted-foreground">{formatRelativeTime(entry.createdAt)}</Text>
          </View>
        ))}
      </View>
    </View>
  );
}
