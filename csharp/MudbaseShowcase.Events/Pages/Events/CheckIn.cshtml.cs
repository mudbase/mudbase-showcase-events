using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.Events.Models;
using MudbaseShowcase.Events.Services;

namespace MudbaseShowcase.Events.Pages.Events;

/// <summary>
/// Organizer-only, owner-only manual QR-token check-in: a single text input for a pasted/typed
/// `qrToken`. Mirrors ../../../web/src/app/events/[id]/checkin/page.tsx + CheckInForm.tsx.
/// </summary>
public sealed class CheckInModel : PageModel
{
    private readonly EventsService _events;
    private readonly BookingsService _bookings;
    private readonly MudbaseSessionAccessor _session;

    public CheckInModel(EventsService events, BookingsService bookings, MudbaseSessionAccessor session)
    {
        _events = events;
        _bookings = bookings;
        _session = session;
    }

    [BindProperty(SupportsGet = true)]
    public string Id { get; set; } = string.Empty;

    [BindProperty]
    public string QrToken { get; set; } = string.Empty;

    public EventDocument? Event { get; private set; }

    public CheckInResult? Result { get; private set; }

    public string? ErrorMessage { get; private set; }

    public async Task<IActionResult> OnGetAsync(CancellationToken cancellationToken)
    {
        IActionResult? guard = await LoadAndGuardAsync(cancellationToken);
        return guard ?? Page();
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        IActionResult? guard = await LoadAndGuardAsync(cancellationToken);
        if (guard is not null) return guard;

        if (string.IsNullOrWhiteSpace(QrToken))
        {
            ModelState.AddModelError(nameof(QrToken), "Paste or type the scanned code");
            return Page();
        }

        try
        {
            Result = await _bookings.CheckInAsync(Id, QrToken, cancellationToken);
        }
        catch (MudbaseApiException ex)
        {
            ErrorMessage = "Couldn't complete check-in. (" + ex.Message + ")";
        }

        // Reset the input for the next scan, mirroring CheckInForm.tsx's reset() after submit.
        QrToken = string.Empty;
        return Page();
    }

    /// <summary>Shared organizer+owner guard for both handlers. Returns a redirect result when access is denied, or null when the caller may proceed (with <see cref="Event"/> populated).</summary>
    private async Task<IActionResult?> LoadAndGuardAsync(CancellationToken cancellationToken)
    {
        MudbaseSessionUser? user = _session.CurrentUser;
        if (user is null) return RedirectToPage("/Login");
        if (!Rbac.IsOrganizer(user.CustomRole)) return RedirectToPage("/Events/Detail", new { id = Id });

        Event = await _events.GetAsync(Id, cancellationToken);
        if (Event is null || Event.OrganizerId != user.Id) return RedirectToPage("/Events/Detail", new { id = Id });

        return null;
    }
}
