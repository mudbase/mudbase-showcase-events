import { View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { AppHeader } from "@/components/layout/AppHeader";
import { BookingList } from "@/components/bookings/BookingList";

export default function BookingsScreen(): React.JSX.Element {
  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <View className="flex-1">
        <AppHeader title="My bookings" />
        <BookingList />
      </View>
    </SafeAreaView>
  );
}
