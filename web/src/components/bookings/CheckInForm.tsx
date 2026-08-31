"use client"

import { useState } from "react"
import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { z } from "zod"
import { CheckCircle2, XCircle, AlertTriangle } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useCheckIn, type CheckInResult } from "@/hooks/useBookings"

const schema = z.object({
  qrToken: z.string().min(1, "Paste or type the scanned code"),
})

type FormValues = z.infer<typeof schema>

const RESULT_COPY: Record<CheckInResult["outcome"], { icon: React.ComponentType<{ className?: string }>; tone: string; message: (name?: string) => string }> = {
  checked_in: {
    icon: CheckCircle2,
    tone: "text-success",
    message: (name) => `${name ?? "Guest"} is checked in.`,
  },
  already_checked_in: {
    icon: AlertTriangle,
    tone: "text-warning",
    message: (name) => `${name ?? "This guest"} was already checked in.`,
  },
  waitlisted: {
    icon: AlertTriangle,
    tone: "text-warning",
    message: (name) => `${name ?? "This guest"} is on the waitlist, not confirmed - cannot check in.`,
  },
  cancelled: {
    icon: XCircle,
    tone: "text-destructive",
    message: (name) => `${name ?? "This booking"} was cancelled.`,
  },
  not_found: {
    icon: XCircle,
    tone: "text-destructive",
    message: () => "No booking found for this code at this event.",
  },
}

export function CheckInForm({ eventId }: { eventId: string }): React.JSX.Element {
  const checkIn = useCheckIn()
  const [result, setResult] = useState<CheckInResult | null>(null)
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<FormValues>({ resolver: zodResolver(schema) })

  const onSubmit = async (values: FormValues): Promise<void> => {
    const outcome = await checkIn.mutateAsync({ eventId, qrToken: values.qrToken })
    setResult(outcome)
    reset()
  }

  const copy = result ? RESULT_COPY[result.outcome] : null
  const Icon = copy?.icon

  return (
    <div className="space-y-4">
      <form onSubmit={handleSubmit(onSubmit)} className="flex items-end gap-3" noValidate>
        <div className="flex-1 space-y-1.5">
          <Label htmlFor="qrToken">Scanned / pasted code</Label>
          <Input id="qrToken" autoFocus placeholder="e.g. 9f2c1a4b…" {...register("qrToken")} />
          {errors.qrToken && <p className="text-xs text-destructive">{errors.qrToken.message}</p>}
        </div>
        <Button type="submit" disabled={checkIn.isPending}>
          {checkIn.isPending ? "Checking…" : "Check in"}
        </Button>
      </form>

      {copy && Icon && (
        <div className={`flex items-center gap-2 rounded-md border border-border bg-secondary/40 p-3 text-sm ${copy.tone}`}>
          <Icon className="h-5 w-5 shrink-0" />
          <span>{copy.message(result?.booking?.userName)}</span>
        </div>
      )}
    </div>
  )
}
