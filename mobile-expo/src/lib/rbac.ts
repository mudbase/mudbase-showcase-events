import { appRoleSchema, type AppRole } from "@/api/schemas";

/**
 * Client-side mirror of the RBAC matrix Mudbase's own collection permissions
 * already enforce server-side (see plan/build-plan.md). This exists purely to
 * hide/disable controls a role cannot use and to show a clear reason why - it
 * is NOT the security boundary. A raw API call bypassing this UI is still
 * rejected by the platform; see the smoke test in build-plan.md. Byte-for-byte
 * port of web/src/hooks/useAuth.ts's role derivation, extracted here so
 * screens/components share one place to ask "can this role do X".
 */
export function canManageEvent(role: AppRole | null, organizerId: string, userId: string | undefined): boolean {
  return role === "organizer" && !!userId && organizerId === userId;
}

export function isOrganizer(role: AppRole | null): boolean {
  return role === "organizer";
}

export function isAttendee(role: AppRole | null): boolean {
  return role === "attendee";
}

export function roleLabel(role: AppRole | null): string {
  if (role === "organizer") return "Organizer";
  if (role === "attendee") return "Attendee";
  return "Unknown";
}

export function isAppRole(value: string | null | undefined): value is AppRole {
  return appRoleSchema.safeParse(value).success;
}
