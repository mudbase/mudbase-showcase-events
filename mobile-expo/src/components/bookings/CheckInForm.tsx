import { useState } from "react";
import { Controller, useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Text, View } from "react-native";
import { CheckCircle2, XCircle, AlertTriangle, type LucideIcon } from "lucide-react-native";
import { z } from "zod";
import { TextField } from "@/components/ui/TextField";
import { Button } from "@/components/ui/Button";
import { useCheckIn, type CheckInResult, type CheckInOutcome } from "@/hooks/useBookings";

const checkInSchema = z.object({
  qrToken: z.string().min(1, "Paste or type the scanned code"),
});

type CheckInFormValues = z.infer<typeof checkInSchema>;

const RESULT_COPY: Record<CheckInOutcome, { icon: LucideIcon; tone: string; message: (name?: string) => string }> = {
  checked_in: {
    icon: CheckCircle2,
    tone: "#16794f",
    message: (name) => `${name ?? "Guest"} is checked in.`,
  },
  already_checked_in: {
    icon: AlertTriangle,
    tone: "#b8790a",
    message: (name) => `${name ?? "This guest"} was already checked in.`,
  },
  waitlisted: {
    icon: AlertTriangle,
    tone: "#b8790a",
    message: (name) => `${name ?? "This guest"} is on the waitlist, not confirmed — cannot check in.`,
  },
  cancelled: {
    icon: XCircle,
    tone: "#e42545",
    message: (name) => `${name ?? "This booking"} was cancelled.`,
  },
  not_found: {
    icon: XCircle,
    tone: "#e42545",
    message: () => "No booking found for this code at this event.",
  },
};

/** Mirrors web/src/components/bookings/CheckInForm.tsx. */
export function CheckInForm({ eventId }: { eventId: string }): React.JSX.Element {
  const checkIn = useCheckIn();
  const [result, setResult] = useState<CheckInResult | null>(null);
  const {
    control,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<CheckInFormValues>({ resolver: zodResolver(checkInSchema), defaultValues: { qrToken: "" } });

  const onSubmit = async (values: CheckInFormValues): Promise<void> => {
    const outcome = await checkIn.mutateAsync({ eventId, qrToken: values.qrToken });
    setResult(outcome);
    reset({ qrToken: "" });
  };

  const copy = result ? RESULT_COPY[result.outcome] : null;
  const Icon = copy?.icon;

  return (
    <View className="gap-4">
      <Controller
        control={control}
        name="qrToken"
        render={({ field: { onChange, onBlur, value } }) => (
          <TextField
            label="Scanned / pasted code"
            value={value}
            onChangeText={onChange}
            onBlur={onBlur}
            autoFocus
            autoCapitalize="none"
            placeholder="e.g. 9f2c1a4b…"
            error={errors.qrToken?.message}
          />
        )}
      />
      <Button isLoading={checkIn.isPending} onPress={handleSubmit(onSubmit)}>
        {checkIn.isPending ? "Checking…" : "Check in"}
      </Button>

      {copy && Icon && (
        <View
          className="flex-row items-center gap-2 rounded-md border border-border bg-secondary/40 p-3"
          accessibilityRole="alert"
        >
          <Icon size={18} color={copy.tone} />
          <Text style={{ color: copy.tone }} className="flex-1 text-sm">
            {copy.message(result?.booking?.userName)}
          </Text>
        </View>
      )}
    </View>
  );
}
