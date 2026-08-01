package dev.mudbase.showcase.events.support;

/**
 * Thrown when a controller/service operates on an event id that doesn't resolve to a real
 * document - either it never existed or was already deleted by its organizer. Handled by {@code
 * dev.mudbase.showcase.events.web.GlobalExceptionHandler}, which renders a plain 404 error page
 * rather than a stack trace.
 */
public class EventNotFoundException extends RuntimeException {

  private static final long serialVersionUID = 1L;

  public EventNotFoundException(String eventId) {
    super("This event is no longer available.");
  }
}
