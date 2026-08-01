import { Text, View } from "react-native";
import { LogOut } from "lucide-react-native";
import { useAuth } from "@/hooks/useAuth";
import { Badge, type BadgeVariant } from "@/components/ui/Badge";
import { IconButton } from "@/components/ui/IconButton";
import { roleLabel } from "@/lib/rbac";

const roleBadgeVariant: Record<"organizer" | "attendee", BadgeVariant> = {
  organizer: "default",
  attendee: "secondary",
};

/**
 * A small per-screen header (title, current-user role badge, sign-out button) shown at the top
 * of each tab screen's content. Expo Router's native stack header does not carry per-role state
 * naturally and there is no meaningful mobile equivalent of the web reference's persistent app
 * shell across a bottom-tab layout, so this renders inline instead — mirrors the content of
 * web/src/components/layout/Header.tsx.
 */
export function AppHeader({ title }: { title: string }): React.JSX.Element {
  const { user, role, logout } = useAuth();

  return (
    <View className="flex-row items-center justify-between px-4 pb-3 pt-2">
      <View className="gap-0.5">
        <Text className="text-2xl font-bold text-foreground">{title}</Text>
        {user && (
          <Text className="text-xs text-muted-foreground">
            {user.firstName} {user.lastName}
          </Text>
        )}
      </View>
      <View className="flex-row items-center gap-2">
        {role && <Badge variant={roleBadgeVariant[role]}>{roleLabel(role)}</Badge>}
        <IconButton accessibilityLabel="Sign out" onPress={() => void logout()}>
          <LogOut size={18} color="#606876" />
        </IconButton>
      </View>
    </View>
  );
}
