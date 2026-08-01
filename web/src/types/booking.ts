import type { Document } from "@/lib/mudbase"

export type BookingStatus = "confirmed" | "waitlisted" | "cancelled" | "checked_in"

export interface BookingDoc extends Document {
  eventId: string
  userId: string
  userName: string
  status: BookingStatus
  qrToken: string
}
