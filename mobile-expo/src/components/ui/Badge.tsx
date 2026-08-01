import { Text, View } from "react-native";
import { cn } from "@/lib/cn";

/** Extends the sibling kanban port's Badge with "success"/"warning" variants — this app's
 * CapacityBadge/BookingCard status pills need all five, mirroring web/src/components/ui/badge.tsx. */
export type BadgeVariant = "default" | "secondary" | "outline" | "success" | "warning" | "destructive";

const variantClasses: Record<BadgeVariant, string> = {
  default: "bg-primary",
  secondary: "bg-secondary",
  outline: "border border-border bg-transparent",
  success: "bg-success",
  warning: "bg-warning",
  destructive: "bg-destructive",
};

const textVariantClasses: Record<BadgeVariant, string> = {
  default: "text-primary-foreground",
  secondary: "text-secondary-foreground",
  outline: "text-foreground",
  success: "text-success-foreground",
  warning: "text-warning-foreground",
  destructive: "text-destructive-foreground",
};

export interface BadgeProps {
  children: string;
  variant?: BadgeVariant;
  className?: string;
  pulse?: boolean;
}

export function Badge({ children, variant = "default", className, pulse = false }: BadgeProps): React.JSX.Element {
  return (
    <View className={cn("rounded-full px-2.5 py-1", variantClasses[variant], pulse && "opacity-60", className)}>
      <Text className={cn("text-xs font-semibold", textVariantClasses[variant])}>{children}</Text>
    </View>
  );
}
