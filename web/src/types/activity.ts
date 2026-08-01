import type { Document } from "@/lib/mudbase"

export type ActivityAction =
  | "booking_confirmed"
  | "booking_waitlisted"
  | "booking_cancelled"
  | "booking_promoted"
  | "checked_in"
  | "event_created"
  | "event_updated"

export interface ActivityDoc extends Document {
  eventId: string
  actorId: string
  actorName: string
  action: ActivityAction
}

export const ACTIVITY_LABELS: Record<ActivityAction, string> = {
  booking_confirmed: "booked (confirmed)",
  booking_waitlisted: "joined the waitlist",
  booking_cancelled: "cancelled their booking",
  booking_promoted: "was promoted from the waitlist",
  checked_in: "checked in",
  event_created: "created this event",
  event_updated: "updated this event",
}
