import "../global.css";
import { useEffect } from "react";
import { ActivityIndicator, View } from "react-native";
import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { AppProviders } from "@/providers/AppProviders";
import { useAuthStore } from "@/stores/authStore";

function BootSplash(): React.JSX.Element {
  return (
    <View className="flex-1 items-center justify-center bg-background">
      <ActivityIndicator size="large" color="#4a43db" />
    </View>
  );
}

function RootNavigator(): React.JSX.Element {
  const isInitializing = useAuthStore((s) => s.isInitializing);

  useEffect(() => {
    void useAuthStore.getState().initialize();
  }, []);

  if (isInitializing) return <BootSplash />;

  return (
    <>
      <StatusBar style="auto" />
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="login" options={{ headerShown: true, title: "Sign in", presentation: "modal" }} />
        <Stack.Screen name="events/new" options={{ headerShown: true, title: "New event", presentation: "modal" }} />
        <Stack.Screen name="events/[id]/index" options={{ headerShown: true, title: "Event" }} />
        <Stack.Screen name="events/[id]/edit" options={{ headerShown: true, title: "Edit event" }} />
        <Stack.Screen name="events/[id]/checkin" options={{ headerShown: true, title: "Check in" }} />
      </Stack>
    </>
  );
}

export default function RootLayout(): React.JSX.Element {
  return (
    <AppProviders>
      <RootNavigator />
    </AppProviders>
  );
}
