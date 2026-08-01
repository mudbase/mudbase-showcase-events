import { z } from "zod";

/**
 * Runtime validation for every Mudbase response shape this app touches.
 *
 * The generated `mudbase-sdk`'s auth response models (e.g.
 * `LoginLocalUser200ResponseUser`) omit `customRole` even though the live API
 * includes it on every project-scoped session response (this app's entire
 * RBAC gating depends on it) — the same gap the sibling
 * `mudbase-showcase-kanban/mobile-expo` port's `schemas.ts` documents against
 * the same generated SDK. Likewise `DataResponse`/`DataListResponse` type
 * their `data` field as bare `object`. Rather than casting past the generated
 * types with `as`, every SDK response is widened to `unknown` (always
 * assignable, no cast needed) and parsed through one of these schemas
 * instead.
 */

// ─── Auth / User ────────────────────────────────────────────────────────────

/** Role slugs this project's multi-role auth is configured with — see plan/build-plan.md. */
export const appRoleSchema = z.enum(["organizer", "attendee"]);
export type AppRole = z.infer<typeof appRoleSchema>;

export const mudbaseUserSchema = z.object({
  id: z.string(),
  email: z.string(),
  firstName: z.string(),
  lastName: z.string(),
  customRole: z.string().nullable().optional(),
  emailVerified: z.boolean().optional(),
});
export type MudbaseUser = z.infer<typeof mudbaseUserSchema>;

export const authResultSchema = z.object({
  message: z.string().optional(),
  token: z.string().optional(),
  refreshToken: z.string().optional(),
  expiresIn: z.number().optional(),
  requireVerification: z.boolean().optional(),
  user: mudbaseUserSchema.optional(),
});
export type AuthResult = z.infer<typeof authResultSchema>;

// ─── Documents (Collections) ───────────────────────────────────────────────

export const documentBaseSchema = z.object({
  _id: z.string(),
  createdAt: z.string(),
  updatedAt: z.string(),
});

export const eventDocSchema = documentBaseSchema.extend({
  title: z.string(),
  description: z.string().nullable().optional(),
  /** ISO date-time string. */
  startsAt: z.string(),
  location: z.string(),
  capacity: z.number(),
  organizerId: z.string(),
  organizerName: z.string(),
});
export type EventDoc = z.infer<typeof eventDocSchema>;

export const bookingStatusSchema = z.enum(["confirmed", "waitlisted", "cancelled", "checked_in"]);
export type BookingStatus = z.infer<typeof bookingStatusSchema>;

export const bookingDocSchema = documentBaseSchema.extend({
  eventId: z.string(),
  userId: z.string(),
  userName: z.string(),
  status: bookingStatusSchema,
  qrToken: z.string(),
});
export type BookingDoc = z.infer<typeof bookingDocSchema>;

export const activityActionSchema = z.enum([
  "booking_confirmed",
  "booking_waitlisted",
  "booking_cancelled",
  "booking_promoted",
  "checked_in",
  "event_created",
  "event_updated",
]);
export type ActivityAction = z.infer<typeof activityActionSchema>;

export const activityEntrySchema = documentBaseSchema.extend({
  eventId: z.string(),
  actorId: z.string(),
  actorName: z.string(),
  action: activityActionSchema,
});
export type ActivityEntry = z.infer<typeof activityEntrySchema>;

export const ACTIVITY_LABELS: Record<ActivityAction, string> = {
  booking_confirmed: "booked (confirmed)",
  booking_waitlisted: "joined the waitlist",
  booking_cancelled: "cancelled their booking",
  booking_promoted: "was promoted from the waitlist",
  checked_in: "checked in",
  event_created: "created this event",
  event_updated: "updated this event",
};
