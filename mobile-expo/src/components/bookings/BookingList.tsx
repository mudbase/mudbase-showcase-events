import { useCallback, useState } from "react";
import { ActivityIndicator, FlatList, RefreshControl, Text, View } from "react-native";
import { Ticket } from "lucide-react-native";
import { useAuth } from "@/hooks/useAuth";
import { useMyBookings, useCancelBooking } from "@/hooks/useBookings";
import { useEventsByIds } from "@/hooks/useEvents";
import { BookingCard } from "@/components/bookings/BookingCard";
import type { BookingDoc } from "@/api/schemas";

/** Mirrors web/src/components/bookings/BookingList.tsx. Uses a real FlatList (unlike the demo-scale
 * event list's plain ScrollView) since a prolific bookings history is the one list in this app that
 * can plausibly grow past a handful of rows. */
export function BookingList(): React.JSX.Element {
  const { user } = useAuth();
  const { data, isLoading, isRefetching, refetch } = useMyBookings(user?.id);
  const bookings = data?.data ?? [];
  const { byId: eventsById } = useEventsByIds(bookings.map((b) => b.eventId));
  const cancelBooking = useCancelBooking();
  const [cancellingId, setCancellingId] = useState<string | null>(null);

  const handleCancel = useCallback(
    async (booking: BookingDoc): Promise<void> => {
      const event = eventsById.get(booking.eventId);
      if (!event || !user) return;
      setCancellingId(booking._id);
      try {
        await cancelBooking.mutateAsync({
          bookingId: booking._id,
          eventId: booking.eventId,
          capacity: event.capacity,
          userId: user.id,
          userName: `${user.firstName} ${user.lastName}`.trim(),
        });
      } finally {
        setCancellingId(null);
      }
    },
    [cancelBooking, eventsById, user],
  );

  const renderItem = useCallback(
    ({ item }: { item: BookingDoc }) => (
      <BookingCard
        booking={item}
        event={eventsById.get(item.eventId)}
        onCancel={(b) => void handleCancel(b)}
        cancelling={cancellingId === item._id}
      />
    ),
    [eventsById, handleCancel, cancellingId],
  );

  if (isLoading) {
    return (
      <View className="flex-1 items-center justify-center py-16">
        <ActivityIndicator size="large" color="#4a43db" />
      </View>
    );
  }

  return (
    <FlatList
      data={bookings}
      keyExtractor={(item) => item._id}
      renderItem={renderItem}
      contentContainerClassName="gap-3 px-4 pb-8"
      refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={() => void refetch()} tintColor="#4a43db" />}
      ListEmptyComponent={
        <View className="items-center gap-2 py-16">
          <Ticket size={28} color="#606876" />
          <Text className="text-sm text-muted-foreground">You haven&apos;t booked any events yet.</Text>
        </View>
      }
    />
  );
}
