import { useState } from "react";
import { Text, View } from "react-native";
import { router } from "expo-router";
import { useAuth } from "@/hooks/useAuth";
import { useCreateBooking, useMyBookingForEvent } from "@/hooks/useBookings";
import { Button } from "@/components/ui/Button";
import { Badge } from "@/components/ui/Badge";
import type { EventDoc } from "@/api/schemas";

const STATUS_LABEL: Record<string, string> = {
  confirmed: "You're booked",
  waitlisted: "You're on the waitlist",
  checked_in: "You're checked in",
  cancelled: "Booking cancelled",
};

/** Mirrors web/src/components/events/BookButton.tsx. */
export function BookButton({ event }: { event: EventDoc }): React.JSX.Element | null {
  const { user, isAuthenticated } = useAuth();
  const [feedback, setFeedback] = useState<string | null>(null);
  const { data: existing, isLoading: existingLoading } = useMyBookingForEvent(event._id, user?.id);
  const createBooking = useCreateBooking();

  const isOwnEvent = !!user && event.organizerId === user.id;
  if (isOwnEvent) return null;

  if (!isAuthenticated || !user) {
    return (
      <Button onPress={() => router.push("/login")}>Sign in to book</Button>
    );
  }

  if (existingLoading) {
    return (
      <Button disabled variant="outline">
        Checking your booking…
      </Button>
    );
  }

  const activeBooking = existing?.data.find((b) => b.status !== "cancelled");
  if (activeBooking) {
    return (
      <View className="flex-row items-center gap-2">
        <Badge variant={activeBooking.status === "waitlisted" ? "warning" : "success"}>
          {STATUS_LABEL[activeBooking.status] ?? activeBooking.status}
        </Badge>
        <Button variant="outline" size="sm" onPress={() => router.push("/bookings")}>
          View my bookings
        </Button>
      </View>
    );
  }

  const handleBook = async (): Promise<void> => {
    setFeedback(null);
    try {
      const booking = await createBooking.mutateAsync({
        eventId: event._id,
        capacity: event.capacity,
        userId: user.id,
        userName: `${user.firstName} ${user.lastName}`.trim(),
      });
      setFeedback(
        booking.status === "confirmed"
          ? "You're confirmed! See your ticket under My bookings."
          : "This event is full — you've been added to the waitlist.",
      );
    } catch {
      setFeedback("Couldn't complete your booking. Please try again.");
    }
  };

  return (
    <View className="gap-2">
      <Button isLoading={createBooking.isPending} onPress={() => void handleBook()}>
        {createBooking.isPending ? "Booking…" : "Book this event"}
      </Button>
      {feedback && <Text className="text-sm text-muted-foreground">{feedback}</Text>}
    </View>
  );
}
