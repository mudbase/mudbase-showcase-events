import { ScrollView, Text, View } from "react-native";
import { router } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { LoginForm } from "@/components/auth/LoginForm";

export default function LoginScreen(): React.JSX.Element {
  return (
    <SafeAreaView className="flex-1 bg-background" edges={["bottom"]}>
      <ScrollView contentContainerClassName="flex-grow justify-center px-6 py-10" keyboardShouldPersistTaps="handled">
        <View className="mb-8 gap-1">
          <Text className="text-3xl font-semibold text-foreground">Mudbase Events</Text>
          <Text className="text-muted-foreground">Sign in to book, manage, or check guests in.</Text>
        </View>
        {/* router.replace (not back()) since /login is reached by a redirect, not a user
            navigation — there is nothing meaningful to go "back" to. */}
        <LoginForm onSuccess={() => router.replace("/")} />
      </ScrollView>
    </SafeAreaView>
  );
}
