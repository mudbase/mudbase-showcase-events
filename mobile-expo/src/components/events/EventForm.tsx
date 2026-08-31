import { useState } from "react";
import { Controller, useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Platform, Text, View } from "react-native";
import DateTimePicker, { type DateTimePickerEvent } from "@react-native-community/datetimepicker";
import { CalendarDays, Clock } from "lucide-react-native";
import { z } from "zod";
import { TextField } from "@/components/ui/TextField";
import { Button } from "@/components/ui/Button";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { formatDateTime } from "@/lib/format";

// `capacity` stays a plain `z.string()` in the RHF-facing schema rather than `z.coerce.number()` -
// zod v4's coerce schemas type their *input* as `unknown` (distinct from their `number` output),
// which the installed @hookform/resolvers/zod version cannot reconcile against a single-generic
// `useForm<EventFormValues>()` call. Validating the raw digits as a string and converting to a
// number only in `handleFormSubmit` below keeps the external `EventFormValues` contract (the type
// every screen in this app consumes) exactly as simple as the web reference's `EventFormValues`.
const eventFormSchema = z.object({
  title: z.string().min(1, "Title is required").max(200, "Title is too long"),
  description: z.string().max(2000, "Description is too long").optional(),
  startsAt: z.date(),
  location: z.string().min(1, "Location is required").max(200, "Location is too long"),
  capacity: z
    .string()
    .min(1, "Capacity is required")
    .regex(/^\d+$/, "Capacity must be a whole number")
    .refine((v) => Number(v) >= 1, "Capacity must be at least 1")
    .refine((v) => Number(v) <= 100000, "Capacity is unrealistically large"),
});

type EventFormSchemaValues = z.infer<typeof eventFormSchema>;

export interface EventFormValues {
  title: string;
  description?: string;
  startsAt: Date;
  location: string;
  capacity: number;
}

interface EventFormProps {
  defaultValues?: Partial<EventFormValues>;
  onSubmit: (values: EventFormValues) => Promise<void>;
  submitting: boolean;
  submitLabel: string;
  errorMessage?: string | null;
}

/**
 * Create/edit event form. React Native has no equivalent of the web reference's
 * `<input type="datetime-local">`, so date and time are picked with two separate native pickers
 * (`@react-native-community/datetimepicker`, mode="date" then mode="time") combined into one
 * `Date` - buttons + a native picker, per this port's "no drag-and-drop, use buttons/pickers"
 * convention. Mirrors web/src/components/events/EventForm.tsx's validation and field set.
 */
export function EventForm({
  defaultValues,
  onSubmit,
  submitting,
  submitLabel,
  errorMessage,
}: EventFormProps): React.JSX.Element {
  const [showDatePicker, setShowDatePicker] = useState(false);
  const [showTimePicker, setShowTimePicker] = useState(false);

  const {
    control,
    handleSubmit,
    formState: { errors },
  } = useForm<EventFormSchemaValues>({
    resolver: zodResolver(eventFormSchema),
    defaultValues: {
      title: defaultValues?.title ?? "",
      description: defaultValues?.description ?? "",
      startsAt: defaultValues?.startsAt ?? new Date(),
      location: defaultValues?.location ?? "",
      capacity: String(defaultValues?.capacity ?? 20),
    },
  });

  const handleFormSubmit = (values: EventFormSchemaValues): Promise<void> =>
    onSubmit({
      title: values.title,
      description: values.description,
      startsAt: values.startsAt,
      location: values.location,
      capacity: Number(values.capacity),
    });

  return (
    <View className="gap-4">
      {errorMessage && <ErrorNotice message={errorMessage} />}

      <Controller
        control={control}
        name="title"
        render={({ field: { onChange, onBlur, value } }) => (
          <TextField
            label="Title"
            value={value}
            onChangeText={onChange}
            onBlur={onBlur}
            placeholder="e.g. Product launch meetup"
            error={errors.title?.message}
          />
        )}
      />

      <Controller
        control={control}
        name="description"
        render={({ field: { onChange, onBlur, value } }) => (
          <TextField
            label="Description (optional)"
            value={value}
            onChangeText={onChange}
            onBlur={onBlur}
            multiline
            numberOfLines={4}
            className="min-h-24"
            textAlignVertical="top"
            error={errors.description?.message}
          />
        )}
      />

      <Controller
        control={control}
        name="startsAt"
        render={({ field: { onChange, value } }) => {
          const handleDateChange = (event: DateTimePickerEvent, selected?: Date): void => {
            if (Platform.OS === "android") setShowDatePicker(false);
            if (event.type === "dismissed" || !selected) return;
            const next = new Date(value);
            next.setFullYear(selected.getFullYear(), selected.getMonth(), selected.getDate());
            onChange(next);
          };

          const handleTimeChange = (event: DateTimePickerEvent, selected?: Date): void => {
            if (Platform.OS === "android") setShowTimePicker(false);
            if (event.type === "dismissed" || !selected) return;
            const next = new Date(value);
            next.setHours(selected.getHours(), selected.getMinutes(), 0, 0);
            onChange(next);
          };

          return (
            <View className="gap-1.5">
              <Text className="text-sm font-medium text-foreground">Date &amp; time</Text>
              <View className="flex-row gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  className="flex-1"
                  icon={<CalendarDays size={14} color="#181c25" />}
                  onPress={() => setShowDatePicker(true)}
                >
                  {new Intl.DateTimeFormat("en-US", { dateStyle: "medium" }).format(value)}
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  className="flex-1"
                  icon={<Clock size={14} color="#181c25" />}
                  onPress={() => setShowTimePicker(true)}
                >
                  {new Intl.DateTimeFormat("en-US", { timeStyle: "short" }).format(value)}
                </Button>
              </View>
              <Text className="text-xs text-muted-foreground">Starts {formatDateTime(value.toISOString())}</Text>

              {showDatePicker && (
                <DateTimePicker value={value} mode="date" display="default" onChange={handleDateChange} />
              )}
              {showTimePicker && (
                <DateTimePicker value={value} mode="time" display="default" onChange={handleTimeChange} />
              )}
              {Platform.OS === "ios" && (showDatePicker || showTimePicker) && (
                <Button
                  variant="ghost"
                  size="sm"
                  onPress={() => {
                    setShowDatePicker(false);
                    setShowTimePicker(false);
                  }}
                >
                  Done
                </Button>
              )}
            </View>
          );
        }}
      />

      <Controller
        control={control}
        name="capacity"
        render={({ field: { onChange, onBlur, value } }) => (
          <TextField
            label="Capacity"
            value={String(value)}
            onChangeText={(text) => onChange(text.replace(/[^0-9]/g, ""))}
            onBlur={onBlur}
            keyboardType="number-pad"
            error={errors.capacity?.message}
          />
        )}
      />

      <Controller
        control={control}
        name="location"
        render={({ field: { onChange, onBlur, value } }) => (
          <TextField
            label="Location"
            value={value}
            onChangeText={onChange}
            onBlur={onBlur}
            placeholder="e.g. 221 Main St, Austin, TX"
            error={errors.location?.message}
          />
        )}
      />

      <Button isLoading={submitting} onPress={handleSubmit(handleFormSubmit)}>
        {submitting ? "Saving…" : submitLabel}
      </Button>
    </View>
  );
}
