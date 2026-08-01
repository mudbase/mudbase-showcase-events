import { useEffect } from "react";
import { Tabs, useRouter } from "expo-router";
import { CalendarDays, Ticket } from "lucide-react-native";
import type { ColorValue } from "react-native";
import { useAuth } from "@/hooks/useAuth";

const FALLBACK_ICON_COLOR = "#181c25";

/**
 * `Tabs.Screen`'s `tabBarIcon` hands back React Navigation's broader
 * `ColorValue`, while lucide-react-native icons only accept a plain `string`.
 * Every tint color configured below is always a literal hex string, so this
 * narrows safely without a cast.
 */
function toIconColor(color: ColorValue): string {
  return typeof color === "string" ? color : FALLBACK_ICON_COLOR;
}

export default function TabsLayout(): React.JSX.Element | null {
  const { isAuthenticated, isInitializing } = useAuth();
  const router = useRouter();

  // This app has no anonymous/guest read (see plan/build-plan.md) — every role, including
  // attendee, must sign in before reaching the events or bookings tabs.
  useEffect(() => {
    if (!isInitializing && !isAuthenticated) {
      router.replace("/login");
    }
  }, [isInitializing, isAuthenticated, router]);

  if (!isAuthenticated) return null;

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: "#4a43db",
        tabBarInactiveTintColor: "#606876",
      }}
    >
      <Tabs.Screen
        name="index"
        options={{ title: "Events", tabBarIcon: ({ color, size }) => <CalendarDays color={toIconColor(color)} size={size} /> }}
      />
      <Tabs.Screen
        name="bookings"
        options={{ title: "My bookings", tabBarIcon: ({ color, size }) => <Ticket color={toIconColor(color)} size={size} /> }}
      />
    </Tabs>
  );
}
