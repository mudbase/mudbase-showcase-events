import { Pressable, Text, View } from "react-native";
import { router } from "expo-router";
import QRCode from "react-native-qrcode-svg";
import { CalendarDays, MapPin } from "lucide-react-native";
import { Card } from "@/components/ui/Card";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { formatDateTime } from "@/lib/format";
import type { BadgeVariant } from "@/components/ui/Badge";
import type { BookingDoc, BookingStatus, EventDoc } from "@/api/schemas";

const STATUS_VARIANT: Record<BookingStatus, BadgeVariant> = {
  confirmed: "success",
  waitlisted: "warning",
  checked_in: "secondary",
  cancelled: "outline",
};

const STATUS_LABEL: Record<BookingStatus, string> = {
  confirmed: "Confirmed",
  waitlisted: "Waitlisted",
  checked_in: "Checked in",
  cancelled: "Cancelled",
};

/** Mirrors web/src/components/bookings/BookingCard.tsx, QR rendered with react-native-qrcode-svg
 * (the RN equivalent of the web reference's qrcode.react `<QRCodeSVG>`). */
export function BookingCard({
  booking,
  event,
  onCancel,
  cancelling,
}: {
  booking: BookingDoc;
  event: EventDoc | undefined;
  onCancel: (booking: BookingDoc) => void;
  cancelling: boolean;
}): React.JSX.Element {
  const canCancel = booking.status === "confirmed" || booking.status === "waitlisted";

  return (
    <Card>
      <View className="flex-row items-start justify-between gap-3">
        <View className="flex-1 gap-1">
          {event ? (
            <Pressable accessibilityRole="button" onPress={() => router.push(`/events/${event._id}`)}>
              <Text className="text-base font-semibold text-primary">{event.title}</Text>
            </Pressable>
          ) : (
            <Text className="text-base font-semibold text-foreground">Event unavailable</Text>
          )}
          {event && (
            <View className="gap-1">
              <View className="flex-row items-center gap-1.5">
                <CalendarDays size={13} color="#606876" />
                <Text className="text-xs text-muted-foreground">{formatDateTime(event.startsAt)}</Text>
              </View>
              <View className="flex-row items-center gap-1.5">
                <MapPin size={13} color="#606876" />
                <Text className="text-xs text-muted-foreground">{event.location}</Text>
              </View>
            </View>
          )}
        </View>
        <Badge variant={STATUS_VARIANT[booking.status]}>{STATUS_LABEL[booking.status]}</Badge>
      </View>

      <View className="mt-3 flex-row items-center justify-between gap-4">
        {booking.status !== "cancelled" ? (
          <View className="flex-row items-center gap-3">
            <View className="rounded-md border border-border bg-white p-2">
              <QRCode value={booking.qrToken} size={64} />
            </View>
            <Text className="max-w-[10rem] flex-shrink font-mono text-xs text-muted-foreground">
              {booking.qrToken}
            </Text>
          </View>
        ) : (
          <Text className="text-sm text-muted-foreground">This booking was cancelled.</Text>
        )}

        {canCancel && (
          <Button variant="outline" size="sm" isLoading={cancelling} onPress={() => onCancel(booking)}>
            {cancelling ? "Cancelling…" : "Cancel"}
          </Button>
        )}
      </View>
    </Card>
  );
}
