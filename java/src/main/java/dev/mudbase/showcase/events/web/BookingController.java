package dev.mudbase.showcase.events.web;

import dev.mudbase.showcase.events.auth.AuthSession;
import dev.mudbase.showcase.events.auth.SessionAuthService;
import dev.mudbase.showcase.events.domain.BookingDoc;
import dev.mudbase.showcase.events.domain.EventDoc;
import dev.mudbase.showcase.events.service.BookingService;
import dev.mudbase.showcase.events.service.EventService;
import dev.mudbase.showcase.events.support.QrImageRenderer;
import dev.mudbase.showcase.events.support.ViewModelHelper;
import jakarta.servlet.http.HttpSession;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;

/**
 * The signed-in user's own bookings across every event (`GET /bookings`) and cancellation
 * (`POST /bookings/{id}/cancel`). Mirrors the reference web app's `/bookings` page.
 */
@Controller
public class BookingController {

  /** One row on the bookings page: the booking, its event (may be null if the event was deleted), and a rendered QR PNG data URI. */
  public record BookingRow(BookingDoc booking, EventDoc event, String qrImageDataUri) {}

  private final BookingService bookingService;
  private final EventService eventService;
  private final ViewModelHelper viewModelHelper;
  private final SessionAuthService sessionAuthService;

  public BookingController(
      BookingService bookingService, EventService eventService, ViewModelHelper viewModelHelper, SessionAuthService sessionAuthService) {
    this.bookingService = bookingService;
    this.eventService = eventService;
    this.viewModelHelper = viewModelHelper;
    this.sessionAuthService = sessionAuthService;
  }

  @GetMapping("/bookings")
  public String myBookings(Model model, HttpSession session) {
    AuthSession viewer = viewModelHelper.addLayoutAttributes(model, session);
    List<BookingDoc> bookings = bookingService.myBookings(viewer);

    // Resolve each booking's event, joining in-memory rather than a real query join (a generic-
    // CRUD BaaS has no cross-collection joins) - a small cache avoids re-fetching the same event
    // twice when a user holds more than one booking for it.
    Map<String, EventDoc> eventsById = new HashMap<>();
    List<BookingRow> rows =
        bookings.stream()
            .map(
                booking -> {
                  EventDoc event =
                      eventsById.computeIfAbsent(
                          booking.getEventId(), eventId -> eventService.findById(viewer.getToken(), eventId).orElse(null));
                  String qrImage = booking.isCancelled() ? null : QrImageRenderer.renderPngDataUri(booking.getQrToken());
                  return new BookingRow(booking, event, qrImage);
                })
            .toList();

    model.addAttribute("rows", rows);
    return "bookings/list";
  }

  @PostMapping("/bookings/{id}/cancel")
  public String cancel(@PathVariable String id, HttpSession session) {
    AuthSession actor = sessionAuthService.current(session).orElseThrow(IllegalStateException::new);
    bookingService.cancelBooking(actor, id);
    return "redirect:/bookings";
  }
}
