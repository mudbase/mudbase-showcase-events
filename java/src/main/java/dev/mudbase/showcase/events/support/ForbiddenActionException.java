package dev.mudbase.showcase.events.support;

/**
 * Thrown by the service layer ({@code EventService}/{@code BookingService}) when the acting user
 * fails a {@link RoleSupport} and/or ownership check for the requested mutation - e.g. an
 * attendee posting to create an event, or an organizer trying to edit an event they don't
 * themselves organize. This is this Java app's own independent server-side enforcement of the
 * RBAC matrix in plan/build-plan.md: it runs before any call to Mudbase is attempted, so a raw
 * POST to one of this app's own routes that bypasses the Thymeleaf UI's hidden buttons is rejected
 * here - not merely by Mudbase's own collection permissions one layer further down (which
 * independently reject the same request too, per the live smoke test in plan/build-plan.md).
 * Handled by {@code dev.mudbase.showcase.events.web.GlobalExceptionHandler}, which renders a 403
 * error page.
 */
public class ForbiddenActionException extends RuntimeException {

  private static final long serialVersionUID = 1L;

  public ForbiddenActionException(String message) {
    super(message);
  }
}
