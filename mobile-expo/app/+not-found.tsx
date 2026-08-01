import { Link, Stack } from "expo-router";
import { Text, View } from "react-native";

export default function NotFoundScreen(): React.JSX.Element {
  return (
    <>
      <Stack.Screen options={{ title: "Not found" }} />
      <View className="flex-1 items-center justify-center gap-3 bg-background p-6">
        <Text className="text-lg font-semibold text-foreground">This screen doesn&apos;t exist.</Text>
        <Link href="/" className="text-sm text-primary underline">
          Go to home screen
        </Link>
      </View>
    </>
  );
}
