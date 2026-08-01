"use client"

import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { z } from "zod"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"

export const eventFormSchema = z.object({
  title: z.string().min(1, "Title is required").max(200, "Title is too long"),
  description: z.string().max(2000, "Description is too long").optional().or(z.literal("")),
  startsAt: z.string().min(1, "Date and time is required"),
  location: z.string().min(1, "Location is required").max(200, "Location is too long"),
  capacity: z.coerce
    .number({ invalid_type_error: "Capacity must be a number" })
    .int("Capacity must be a whole number")
    .min(1, "Capacity must be at least 1")
    .max(100000, "Capacity is unrealistically large"),
})

export type EventFormValues = z.infer<typeof eventFormSchema>

export function EventForm({
  defaultValues,
  onSubmit,
  submitting,
  submitLabel,
  errorMessage,
}: {
  defaultValues?: Partial<EventFormValues>
  onSubmit: (values: EventFormValues) => Promise<void>
  submitting: boolean
  submitLabel: string
  errorMessage?: string | null
}): React.JSX.Element {
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<EventFormValues>({
    resolver: zodResolver(eventFormSchema),
    defaultValues: {
      title: defaultValues?.title ?? "",
      description: defaultValues?.description ?? "",
      startsAt: defaultValues?.startsAt ?? "",
      location: defaultValues?.location ?? "",
      capacity: defaultValues?.capacity ?? 20,
    },
  })

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-4" noValidate>
      {errorMessage && (
        <p role="alert" className="text-sm text-destructive">
          {errorMessage}
        </p>
      )}

      <div className="space-y-1.5">
        <Label htmlFor="title">Title</Label>
        <Input id="title" {...register("title")} />
        {errors.title && <p className="text-xs text-destructive">{errors.title.message}</p>}
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="description">Description</Label>
        <Textarea id="description" rows={4} {...register("description")} />
        {errors.description && <p className="text-xs text-destructive">{errors.description.message}</p>}
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="startsAt">Date &amp; time</Label>
          <Input id="startsAt" type="datetime-local" {...register("startsAt")} />
          {errors.startsAt && <p className="text-xs text-destructive">{errors.startsAt.message}</p>}
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="capacity">Capacity</Label>
          <Input id="capacity" type="number" min={1} step={1} {...register("capacity")} />
          {errors.capacity && <p className="text-xs text-destructive">{errors.capacity.message}</p>}
        </div>
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="location">Location</Label>
        <Input id="location" {...register("location")} />
        {errors.location && <p className="text-xs text-destructive">{errors.location.message}</p>}
      </div>

      <Button type="submit" className="w-full" disabled={submitting}>
        {submitting ? "Saving…" : submitLabel}
      </Button>
    </form>
  )
}
