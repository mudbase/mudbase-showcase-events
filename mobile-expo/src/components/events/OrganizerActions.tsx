import { useState } from "react";
import { Text, View } from "react-native";
import { router } from "expo-router";
import { Pencil, QrCode, Trash2 } from "lucide-react-native";
import { Button } from "@/components/ui/Button";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useDeleteEvent } from "@/hooks/useEvents";

/** Mirrors web/src/components/events/OrganizerActions.tsx. */
export function OrganizerActions({ eventId }: { eventId: string }): React.JSX.Element {
  const deleteEvent = useDeleteEvent();
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleDelete = async (): Promise<void> => {
    setError(null);
    try {
      await deleteEvent.mutateAsync(eventId);
      router.replace("/");
    } catch {
      setError("Couldn't delete this event. Please try again.");
      setConfirming(false);
    }
  };

  return (
    <View className="gap-2 rounded-md border border-border bg-secondary/40 p-3">
      <Text className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Organizer</Text>
      <View className="flex-row flex-wrap gap-2">
        <Button
          variant="outline"
          size="sm"
          icon={<Pencil size={14} color="#181c25" />}
          onPress={() => router.push(`/events/${eventId}/edit`)}
        >
          Edit
        </Button>
        <Button
          variant="outline"
          size="sm"
          icon={<QrCode size={14} color="#181c25" />}
          onPress={() => router.push(`/events/${eventId}/checkin`)}
        >
          Check-in
        </Button>

        {confirming ? (
          <View className="flex-row items-center gap-2">
            <Button
              variant="destructive"
              size="sm"
              isLoading={deleteEvent.isPending}
              onPress={() => void handleDelete()}
            >
              {deleteEvent.isPending ? "Deleting…" : "Confirm delete"}
            </Button>
            <Button variant="ghost" size="sm" onPress={() => setConfirming(false)}>
              Cancel
            </Button>
          </View>
        ) : (
          <Button
            variant="destructive"
            size="sm"
            icon={<Trash2 size={14} color="#f9f9fb" />}
            onPress={() => setConfirming(true)}
          >
            Delete
          </Button>
        )}
      </View>

      {error && <ErrorNotice message={error} />}
    </View>
  );
}
