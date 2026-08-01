import type { Document } from "@/lib/mudbase"

export interface EventDoc extends Document {
  title: string
  description?: string
  /** ISO date-time string. */
  startsAt: string
  location: string
  capacity: number
  organizerId: string
  organizerName: string
}
