package dev.mudbase.showcase.events.web;

import dev.mudbase.showcase.events.auth.AuthSession;
import dev.mudbase.showcase.events.auth.SessionAuthService;
import dev.mudbase.showcase.events.domain.ActivityEntry;
import dev.mudbase.showcase.events.domain.BookingDoc;
import dev.mudbase.showcase.events.domain.EventDoc;
import dev.mudbase.showcase.events.mudbase.PageResult;
import dev.mudbase.showcase.events.service.ActivityService;
import dev.mudbase.showcase.events.service.BookingService;
import dev.mudbase.showcase.events.service.EventService;
import dev.mudbase.showcase.events.support.RoleSupport;
import dev.mudbase.showcase.events.support.ViewModelHelper;
import dev.mudbase.showcase.events.web.dto.CheckInRequest;
import dev.mudbase.showcase.events.web.dto.EventFormRequest;
import jakarta.servlet.http.HttpSession;
import jakarta.validation.Valid;
import java.util.List;
import java.util.Optional;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

/**
 * Event list/detail/create/edit/delete/check-in - every read is auth-gated ({@link
 * AuthGateInterceptor}), every mutation is additionally enforced by {@code EventService}/{@code
 * BookingService}'s own role + ownership checks (this app's independent server-side security
 * layer, see {@code ForbiddenActionException}'s javadoc) before Mudbase is ever called.
 *
 * <p>GET routes that only a specific role/owner should reach (new/edit/checkin forms) redirect
 * away quietly for the wrong viewer - matching the reference web app's client-side `useEffect`
 * redirect. The mutating POST routes behind them (`create`/`update`/`delete`/`checkin`) are the
 * real security boundary: a request that bypasses the hidden UI and posts directly is rejected
 * with a 403 by {@code EventService}/{@code BookingService} before any Mudbase call is attempted.
 */
@Controller
public class EventController {

  /**
   * One row on the event list: the event plus its live confirmed-booking count. The badge
   * variant/label are precomputed here (rather than with inline expression-language arithmetic
   * in the template) mirroring the reference web app's {@code CapacityBadge} component logic
   * exactly: full once remaining <= 0, a warning once remaining is within 10% of capacity
   * (minimum 1), success otherwise.
   */
  public record EventRow(EventDoc event, long confirmedCount) {

    public String getBadgeVariant() {
      long remaining = event.getCapacity() - confirmedCount;
      if (remaining <= 0) {
        return "badge-destructive";
      }
      long warningThreshold = Math.max(1, Math.round(Math.ceil(event.getCapacity() * 0.1)));
      return remaining <= warningThreshold ? "badge-warning" : "badge-success";
    }

    public String getBadgeLabel() {
      long remaining = event.getCapacity() - confirmedCount;
      if (remaining <= 0) {
        return "Full · " + confirmedCount + "/" + event.getCapacity();
      }
      return confirmedCount + "/" + event.getCapacity() + " booked";
    }
  }

  private final EventService eventService;
  private final BookingService bookingService;
  private final ActivityService activityService;
  private final ViewModelHelper viewModelHelper;
  private final SessionAuthService sessionAuthService;

  public EventController(
      EventService eventService,
      BookingService bookingService,
      ActivityService activityService,
      ViewModelHelper viewModelHelper,
      SessionAuthService sessionAuthService) {
    this.eventService = eventService;
    this.bookingService = bookingService;
    this.activityService = activityService;
    this.viewModelHelper = viewModelHelper;
    this.sessionAuthService = sessionAuthService;
  }

  @GetMapping("/")
  public String list(@RequestParam(value = "page", defaultValue = "1") int page, Model model, HttpSession session) {
    AuthSession viewer = requireViewer(model, session);
    PageResult<EventDoc> events = eventService.listEvents(viewer.getToken(), Math.max(page, 1));
    List<EventRow> rows = events.items().stream().map(e -> new EventRow(e, eventService.confirmedCount(viewer.getToken(), e.getId()))).toList();

    model.addAttribute("rows", rows);
    model.addAttribute("page", events.page());
    model.addAttribute("hasMore", events.hasMore());
    model.addAttribute("hasPrevious", events.page() > 1);
    return "index";
  }

  @GetMapping("/events/new")
  public String newForm(Model model, HttpSession session) {
    AuthSession viewer = requireViewer(model, session);
    if (!RoleSupport.isOrganizer(viewer.getRole())) {
      return "redirect:/";
    }
    if (!model.containsAttribute("eventFormRequest")) {
      model.addAttribute("eventFormRequest", new EventFormRequest());
    }
    model.addAttribute("formTitle", "New event");
    model.addAttribute("formSubtitle", "Set a capacity — bookings beyond it are automatically waitlisted.");
    model.addAttribute("formAction", "/events");
    model.addAttribute("submitLabel", "Create event");
    return "events/form";
  }

  @PostMapping("/events")
  public String create(
      @Valid @ModelAttribute("eventFormRequest") EventFormRequest form,
      BindingResult bindingResult,
      Model model,
      HttpSession session) {
    AuthSession actor = requireViewer(model, session);
    if (bindingResult.hasErrors()) {
      return reRenderCreateForm(model);
    }
    // Deliberately no try/catch here: a role/ownership failure (ForbiddenActionException) or a
    // real Mudbase failure (MudbaseApiException) must propagate to GlobalExceptionHandler, which
    // renders the correct 403/error page - swallowing it into a generic "couldn't create" 200
    // response would silently turn a genuine authorization rejection into what looks like a
    // transient failure, which is exactly the kind of security-relevant bug this port's own
    // live-verification pass is meant to catch (see plan/build-plan.md).
    EventDoc created = eventService.createEvent(actor, form);
    return "redirect:/events/" + created.getId();
  }

  @GetMapping("/events/{id}")
  public String detail(@PathVariable String id, Model model, HttpSession session) {
    AuthSession viewer = requireViewer(model, session);
    Optional<EventDoc> eventOpt = eventService.findById(viewer.getToken(), id);
    if (eventOpt.isEmpty()) {
      model.addAttribute("errorMessage", "This event is no longer available.");
      return "events/not-found";
    }
    EventDoc event = eventOpt.get();
    long confirmedCount = eventService.confirmedCount(viewer.getToken(), id);
    boolean isOwner = event.isOwnedBy(viewer.getUserId());
    BookingDoc myBooking = bookingService.myActiveBookingForEvent(viewer, id).orElse(null);
    List<ActivityEntry> activity = activityService.feed(viewer.getToken(), id);

    model.addAttribute("event", event);
    model.addAttribute("confirmedCount", confirmedCount);
    model.addAttribute("remaining", event.getCapacity() - confirmedCount);
    model.addAttribute("capacityBadge", new EventRow(event, confirmedCount));
    model.addAttribute("isOwner", isOwner);
    model.addAttribute("myBooking", myBooking);
    model.addAttribute("activity", activity);
    return "events/detail";
  }

  @PostMapping("/events/{id}/book")
  public String book(@PathVariable String id, HttpSession session, RedirectAttributes redirectAttributes) {
    AuthSession actor = sessionAuthService.current(session).orElseThrow(IllegalStateException::new);
    EventDoc event = eventService.requireExisting(actor.getToken(), id);
    BookingDoc booking = bookingService.createBooking(actor, event);
    redirectAttributes.addFlashAttribute(
        "bookingMessage",
        BookingDoc.CONFIRMED.equals(booking.getStatus())
            ? "You're confirmed! See your ticket under My bookings."
            : "This event is full — you've been added to the waitlist.");
    return "redirect:/events/" + id;
  }

  @GetMapping("/events/{id}/edit")
  public String editForm(@PathVariable String id, Model model, HttpSession session) {
    AuthSession viewer = requireViewer(model, session);
    Optional<EventDoc> eventOpt = eventService.findById(viewer.getToken(), id);
    if (eventOpt.isEmpty() || !RoleSupport.isOrganizer(viewer.getRole()) || !eventOpt.get().isOwnedBy(viewer.getUserId())) {
      return "redirect:/events/" + id;
    }
    EventDoc event = eventOpt.get();
    if (!model.containsAttribute("eventFormRequest")) {
      EventFormRequest form = new EventFormRequest();
      form.setTitle(event.getTitle());
      form.setDescription(event.getDescription() != null ? event.getDescription() : "");
      form.setStartsAt(event.getStartsAtLocalInputValue());
      form.setLocation(event.getLocation());
      form.setCapacity(event.getCapacity());
      model.addAttribute("eventFormRequest", form);
    }
    model.addAttribute("formTitle", "Edit event");
    model.addAttribute("formSubtitle", "Changes to capacity are re-checked against existing bookings.");
    model.addAttribute("formAction", "/events/" + id + "/edit");
    model.addAttribute("submitLabel", "Save changes");
    return "events/form";
  }

  @PostMapping("/events/{id}/edit")
  public String update(
      @PathVariable String id,
      @Valid @ModelAttribute("eventFormRequest") EventFormRequest form,
      BindingResult bindingResult,
      Model model,
      HttpSession session) {
    AuthSession actor = requireViewer(model, session);
    if (bindingResult.hasErrors()) {
      return reRenderEditForm(model, id);
    }
    // See the identical comment in create(): a ForbiddenActionException/EventNotFoundException/
    // MudbaseApiException must propagate to GlobalExceptionHandler, not be swallowed here.
    eventService.updateEvent(actor, id, form);
    return "redirect:/events/" + id;
  }

  @PostMapping("/events/{id}/delete")
  public String delete(@PathVariable String id, HttpSession session) {
    AuthSession actor = sessionAuthService.current(session).orElseThrow(IllegalStateException::new);
    eventService.deleteEvent(actor, id);
    return "redirect:/";
  }

  @GetMapping("/events/{id}/checkin")
  public String checkinForm(@PathVariable String id, Model model, HttpSession session) {
    AuthSession viewer = requireViewer(model, session);
    Optional<EventDoc> eventOpt = eventService.findById(viewer.getToken(), id);
    if (eventOpt.isEmpty() || !RoleSupport.isOrganizer(viewer.getRole()) || !eventOpt.get().isOwnedBy(viewer.getUserId())) {
      return "redirect:/events/" + id;
    }
    model.addAttribute("event", eventOpt.get());
    if (!model.containsAttribute("checkInRequest")) {
      model.addAttribute("checkInRequest", new CheckInRequest());
    }
    return "events/checkin";
  }

  @PostMapping("/events/{id}/checkin")
  public String checkin(
      @PathVariable String id,
      @Valid @ModelAttribute("checkInRequest") CheckInRequest form,
      BindingResult bindingResult,
      Model model,
      HttpSession session) {
    AuthSession actor = requireViewer(model, session);
    EventDoc event = eventService.requireExisting(actor.getToken(), id);
    model.addAttribute("event", event);

    if (!bindingResult.hasErrors()) {
      BookingService.CheckInResult result = bookingService.checkIn(actor, event, form.getQrToken());
      model.addAttribute("checkInOutcome", result.outcome().name());
      model.addAttribute("checkInGuestName", result.booking() != null ? result.booking().getUserName() : null);
    }
    model.addAttribute("checkInRequest", new CheckInRequest());
    return "events/checkin";
  }

  private AuthSession requireViewer(Model model, HttpSession session) {
    AuthSession viewer = viewModelHelper.addLayoutAttributes(model, session);
    if (viewer == null) {
      // AuthGateInterceptor already guarantees a session for every route reaching this
      // controller - defensive only, never reached in practice.
      throw new IllegalStateException("No signed-in session on a gated route");
    }
    return viewer;
  }

  private String reRenderCreateForm(Model model) {
    model.addAttribute("formTitle", "New event");
    model.addAttribute("formSubtitle", "Set a capacity — bookings beyond it are automatically waitlisted.");
    model.addAttribute("formAction", "/events");
    model.addAttribute("submitLabel", "Create event");
    return "events/form";
  }

  private String reRenderEditForm(Model model, String id) {
    model.addAttribute("formTitle", "Edit event");
    model.addAttribute("formSubtitle", "Changes to capacity are re-checked against existing bookings.");
    model.addAttribute("formAction", "/events/" + id + "/edit");
    model.addAttribute("submitLabel", "Save changes");
    return "events/form";
  }
}
