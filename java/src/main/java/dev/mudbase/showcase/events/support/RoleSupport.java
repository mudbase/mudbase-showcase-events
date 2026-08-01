package dev.mudbase.showcase.events.support;

/**
 * Server-side mirror of the RBAC matrix Mudbase's own collection permissions already enforce
 * (see plan/build-plan.md) - used both to hide/disable controls a role cannot use in the
 * templates, and (via {@link ForbiddenActionException}, thrown from the service layer) as this
 * Java app's own independent server-side check before a mutating Mudbase call is even attempted.
 * Neither of these is the ultimate security boundary - Mudbase's own per-collection permissions
 * are - but together they mean a request that bypasses this app's UI still gets rejected by this
 * app's own controllers/services, not merely by the platform one layer further down.
 *
 * <p>Unlike the sibling Kanban port's board-wide roles, event/booking mutation permission here is
 * also ownership-scoped (an organizer may only edit/delete/check-in on events they themselves
 * organize) - that check lives alongside the role check in {@code EventService}/{@code
 * BookingService}, not here, since it depends on a specific document's {@code organizerId}.
 */
public final class RoleSupport {

  public static final String ORGANIZER = "organizer";
  public static final String ATTENDEE = "attendee";

  private RoleSupport() {}

  public static boolean isOrganizer(String role) {
    return ORGANIZER.equals(role);
  }

  public static String roleLabel(String role) {
    if (ORGANIZER.equals(role)) {
      return "Organizer";
    }
    if (ATTENDEE.equals(role)) {
      return "Attendee";
    }
    return "Unknown";
  }
}
