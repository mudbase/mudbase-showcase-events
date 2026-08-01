using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.Events.Models;
using MudbaseShowcase.Events.Services;

namespace MudbaseShowcase.Events.Pages;

/// <summary>
/// The signed-in user's own bookings across every event, each with its QR ticket and a Cancel
/// action (confirmed/waitlisted only). Mirrors ../../web/src/app/bookings/page.tsx +
/// BookingList.tsx/BookingCard.tsx. Not role-gated beyond "signed in" (already enforced globally
/// by RequireMudbaseSessionMiddleware) - per the reference app's RBAC matrix, an organizer who
/// also holds a booking on someone else's event sees it here too, exactly like the reference's
/// `/bookings` page (which only checks `isAuthenticated`, not role).
/// </summary>
public sealed class BookingsModel : PageModel
{
    private readonly EventsService _events;
    private readonly BookingsService _bookings;
    private readonly MudbaseSessionAccessor _session;

    public BookingsModel(EventsService events, BookingsService bookings, MudbaseSessionAccessor session)
    {
        _events = events;
        _bookings = bookings;
        _session = session;
    }

    public IReadOnlyList<BookingListItemViewModel> Items { get; private set; } = Array.Empty<BookingListItemViewModel>();

    public string? LoadError { get; private set; }

    [TempData]
    public string? FlashError { get; set; }

    public async Task OnGetAsync(CancellationToken cancellationToken)
    {
        MudbaseSessionUser? user = _session.CurrentUser;
        if (user is null) return; // defensive only - RequireMudbaseSessionMiddleware already guarantees a signed-in visitor here

        try
        {
            MudbaseListResult<BookingDocument> mine = await _bookings.ListForUserAsync(user.Id, cancellationToken);

            // Resolve each distinct eventId once in parallel - mirrors useEventsByIds's Map-based
            // dedup, since a generic-CRUD BaaS has no native cross-collection join.
            string[] uniqueEventIds = mine.Items.Select(b => b.EventId).Distinct().ToArray();
            EventDocument?[] fetchedEvents = await Task.WhenAll(uniqueEventIds.Select(id => _events.GetAsync(id, cancellationToken)));

            Dictionary<string, EventDocument> eventsById = new();
            for (int i = 0; i < uniqueEventIds.Length; i++)
            {
                if (fetchedEvents[i] is { } evt) eventsById[uniqueEventIds[i]] = evt;
            }

            Items = mine.Items
                .Select(b => new BookingListItemViewModel { Booking = b, Event = eventsById.GetValueOrDefault(b.EventId) })
                .ToList();
        }
        catch (MudbaseApiException ex)
        {
            LoadError = "Couldn't load your bookings right now. (" + ex.Message + ")";
        }
    }

    /// <summary>
    /// Only `bookingId` is trusted from the client - `eventId`/`capacity` are re-derived
    /// server-side from the booking and event documents themselves, and ownership is verified
    /// before any mutation. Posting an arbitrary hidden-field `eventId`/`capacity` pair (or another
    /// user's `bookingId`) cannot cancel someone else's booking or corrupt another event's capacity
    /// reconciliation - see Services/BookingsService.cs's `GetAsync` doc comment.
    /// </summary>
    public async Task<IActionResult> OnPostCancelAsync(string bookingId, CancellationToken cancellationToken)
    {
        MudbaseSessionUser? user = _session.CurrentUser;
        if (user is null) return RedirectToPage("/Login");

        try
        {
            BookingDocument? booking = await _bookings.GetAsync(bookingId, cancellationToken);
            if (booking is null)
            {
                FlashError = "That booking no longer exists.";
                return RedirectToPage();
            }

            if (booking.UserId != user.Id)
            {
                FlashError = "You can only cancel your own bookings.";
                return RedirectToPage();
            }

            EventDocument? evt = await _events.GetAsync(booking.EventId, cancellationToken);
            // If the event itself was deleted there is nothing left to reconcile capacity
            // against - treat capacity as unbounded so the cancellation still lands cleanly
            // without spuriously touching any other booking.
            int capacity = evt?.Capacity ?? int.MaxValue;

            await _bookings.CancelAsync(booking.Id, booking.EventId, capacity, user.Id, user.DisplayName, cancellationToken);
        }
        catch (MudbaseApiException ex)
        {
            FlashError = "Couldn't cancel this booking. (" + ex.Message + ")";
        }

        return RedirectToPage();
    }
}
