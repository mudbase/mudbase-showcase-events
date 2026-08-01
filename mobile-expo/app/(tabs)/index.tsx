import { View } from "react-native";
import { router } from "expo-router";
import { Plus } from "lucide-react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { AppHeader } from "@/components/layout/AppHeader";
import { EventListScreen } from "@/components/events/EventListScreen";
import { Button } from "@/components/ui/Button";
import { useAuth } from "@/hooks/useAuth";

export default function EventsScreen(): React.JSX.Element {
  const { isOrganizer } = useAuth();

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <View className="flex-1">
        <AppHeader title="Events" />
        {isOrganizer && (
          <View className="px-4 pb-3">
            <Button
              variant="outline"
              size="sm"
              icon={<Plus size={14} color="#181c25" />}
              onPress={() => router.push("/events/new")}
            >
              New event
            </Button>
          </View>
        )}
        <EventListScreen />
      </View>
    </SafeAreaView>
  );
}
