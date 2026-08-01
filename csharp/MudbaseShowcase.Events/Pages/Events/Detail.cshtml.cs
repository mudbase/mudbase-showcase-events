using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.Events.Models;
using MudbaseShowcase.Events.Services;

namespace MudbaseShowcase.Events.Pages.Events;

/// <summary>
/// Full event detail: info, confirmed/capacity indicator, a Book button for the current user when
/// they are not that event's organizer (capacity-race approach, see BookingsService.cs),
/// organizer-only Edit/Delete/Check-in affordances when `OrganizerId == session.user.id`, and the
/// reverse-chronological activity feed for the event. Mirrors ../../../web/src/app/events/[id]/page.tsx.
/// </summary>
public sealed class DetailModel : PageModel
{
    private readonly EventsService _events;
    private readonly BookingsService _bookings;
    private readonly ActivityService _activity;
    private readonly MudbaseSessionAccessor _session;

    public DetailModel(EventsService events, BookingsService bookings, ActivityService activity, MudbaseSessionAccessor session)
    {
        _events = events;
        _bookings = bookings;
        _activity = activity;
        _session = session;
    }

    [BindProperty(SupportsGet = true)]
    public string Id { get; set; } = string.Empty;

    public EventDocument? Event { get; private set; }

    public int ConfirmedCount { get; private set; }

    /// <summary>The signed-in user's own active (non-cancelled) booking for this event, if any.</summary>
    public BookingDocument? MyBooking { get; private set; }

    public IReadOnlyList<ActivityDocument> ActivityEntries { get; private set; } = Array.Empty<ActivityDocument>();

    public bool EventNotFound { get; private set; }

    public string? LoadError { get; private set; }

    [TempData]
    public string? FlashMessage { get; set; }

    [TempData]
    public string? FlashError { get; set; }

    public bool IsOwner { get; private set; }

    /// <summary>True when the signed-in visitor may book this event: signed in, not its organizer, and no active booking already exists.</summary>
    public bool CanBook { get; private set; }

    public async Task OnGetAsync(CancellationToken cancellationToken) => await LoadAsync(cancellationToken);

    public async Task<IActionResult> OnPostBookAsync(CancellationToken cancellationToken)
    {
        MudbaseSessionUser? user = _session.CurrentUser;
        if (user is null) return RedirectToPage("/Login");

        EventDocument? evt = await _events.GetAsync(Id, cancellationToken);
        if (evt is null) return RedirectToPage();

        if (evt.OrganizerId == user.Id)
        {
            FlashError = "You can't book your own event.";
            return RedirectToPage(new { id = Id });
        }

        // Re-check server-side rather than trusting the GET-rendered `CanBook` flag - a double
        // form submission (or a POST replayed outside the UI) must not be able to create two
        // active bookings for the same user/event.
        BookingDocument? existing = await _bookings.GetActiveBookingAsync(Id, user.Id, cancellationToken);
        if (existing is not null)
        {
            FlashError = "You already have a booking for this event.";
            return RedirectToPage(new { id = Id });
        }

        try
        {
            BookingDocument booking = await _bookings.CreateAsync(Id, evt.Capacity, user.Id, user.DisplayName, cancellationToken);
            FlashMessage = booking.Status == BookingStatus.Confirmed
                ? "You're confirmed! See your ticket under My bookings."
                : "This event is full — you've been added to the waitlist.";
        }
        catch (MudbaseApiException ex)
        {
            FlashError = "Couldn't complete your booking. (" + ex.Message + ")";
        }

        return RedirectToPage(new { id = Id });
    }

    /// <summary>Organizer-only, owner-only. Mirrors OrganizerActions.tsx's delete flow (the confirm-then-delete two-step there is a client-side affordance around the same single DELETE call - see Detail.cshtml's native `confirm()` dialog on the form, matching the sibling Kanban port's identical pattern for its own destructive actions).</summary>
    public async Task<IActionResult> OnPostDeleteAsync(CancellationToken cancellationToken)
    {
        MudbaseSessionUser? user = _session.CurrentUser;
        if (user is null) return RedirectToPage("/Login");

        EventDocument? evt = await _events.GetAsync(Id, cancellationToken);
        if (evt is null) return RedirectToPage("/Index");
        if (evt.OrganizerId != user.Id)
        {
            FlashError = "Only this event's organizer can delete it.";
            return RedirectToPage(new { id = Id });
        }

        try
        {
            await _events.DeleteAsync(Id, cancellationToken);
        }
        catch (MudbaseApiException ex)
        {
            FlashError = "Couldn't delete this event. (" + ex.Message + ")";
            return RedirectToPage(new { id = Id });
        }

        return RedirectToPage("/Index");
    }

    private async Task LoadAsync(CancellationToken cancellationToken)
    {
        try
        {
            Event = await _events.GetAsync(Id, cancellationToken);
            if (Event is null)
            {
                EventNotFound = true;
                return;
            }

            ConfirmedCount = await _events.ConfirmedCountAsync(Id, cancellationToken);

            MudbaseSessionUser? user = _session.CurrentUser;
            if (user is not null)
            {
                IsOwner = Event.OrganizerId == user.Id;
                if (!IsOwner)
                {
                    MyBooking = await _bookings.GetActiveBookingAsync(Id, user.Id, cancellationToken);
                }

                CanBook = !IsOwner && MyBooking is null;
            }

            MudbaseListResult<ActivityDocument> activityResult = await _activity.ListForEventAsync(Id, page: 1, limit: 50, cancellationToken);
            ActivityEntries = activityResult.Items;
        }
        catch (MudbaseApiException ex)
        {
            LoadError = "Couldn't load this event right now. (" + ex.Message + ")";
        }
    }
}
