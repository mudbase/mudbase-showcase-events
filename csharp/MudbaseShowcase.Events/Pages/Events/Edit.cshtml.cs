using System.ComponentModel.DataAnnotations;
using System.Globalization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.Events.Models;
using MudbaseShowcase.Events.Services;

namespace MudbaseShowcase.Events.Pages.Events;

/// <summary>
/// Organizer-only, owner-only edit form. Mirrors ../../../web/src/app/events/[id]/edit/page.tsx.
/// Deliberately does NOT re-run capacity reconciliation after a capacity change - neither does the
/// reference app's handleSubmit (verified by reading it directly): a capacity change here is a
/// plain field update plus an `event_updated` activity entry, nothing more. The next booking or
/// cancellation naturally re-derives confirmed/waitlisted against the new capacity via
/// CapacityService, so this isn't a functional gap versus the app it ports.
/// </summary>
public sealed class EditModel : PageModel
{
    private readonly EventsService _events;
    private readonly ActivityService _activity;
    private readonly MudbaseSessionAccessor _session;

    public EditModel(EventsService events, ActivityService activity, MudbaseSessionAccessor session)
    {
        _events = events;
        _activity = activity;
        _session = session;
    }

    [BindProperty(SupportsGet = true)]
    public string Id { get; set; } = string.Empty;

    [BindProperty]
    public EventInput Input { get; set; } = new();

    public string? ErrorMessage { get; private set; }

    public async Task<IActionResult> OnGetAsync(CancellationToken cancellationToken)
    {
        MudbaseSessionUser? user = _session.CurrentUser;
        if (user is null) return RedirectToPage("/Login");
        if (!Rbac.IsOrganizer(user.CustomRole)) return RedirectToPage("/Events/Detail", new { id = Id });

        EventDocument? evt = await _events.GetAsync(Id, cancellationToken);
        if (evt is null || evt.OrganizerId != user.Id) return RedirectToPage("/Events/Detail", new { id = Id });

        Input = new EventInput
        {
            Title = evt.Title,
            Description = evt.Description ?? string.Empty,
            StartsAt = DisplayHelpers.ToDateTimeLocalValue(evt.StartsAt),
            Location = evt.Location,
            Capacity = evt.Capacity,
        };

        return Page();
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        MudbaseSessionUser? user = _session.CurrentUser;
        if (user is null) return RedirectToPage("/Login");
        if (!Rbac.IsOrganizer(user.CustomRole)) return RedirectToPage("/Events/Detail", new { id = Id });

        EventDocument? evt = await _events.GetAsync(Id, cancellationToken);
        if (evt is null || evt.OrganizerId != user.Id) return RedirectToPage("/Events/Detail", new { id = Id });

        if (!ModelState.IsValid)
        {
            return Page();
        }

        if (!DateTime.TryParse(Input.StartsAt, CultureInfo.InvariantCulture, DateTimeStyles.None, out DateTime parsedLocal))
        {
            ModelState.AddModelError("Input.StartsAt", "Enter a valid date and time.");
            return Page();
        }

        DateTimeOffset startsAtUtc = new DateTimeOffset(DateTime.SpecifyKind(parsedLocal, DateTimeKind.Local)).ToUniversalTime();

        try
        {
            await _events.UpdateAsync(
                Id,
                Input.Title.Trim(),
                string.IsNullOrWhiteSpace(Input.Description) ? null : Input.Description.Trim(),
                startsAtUtc,
                Input.Location.Trim(),
                Input.Capacity,
                cancellationToken);

            await _activity.LogAsync(Id, user.Id, user.DisplayName, ActivityActions.EventUpdated, cancellationToken);

            return RedirectToPage("/Events/Detail", new { id = Id });
        }
        catch (MudbaseApiException ex)
        {
            ErrorMessage = "Couldn't save these changes. (" + ex.Message + ")";
            return Page();
        }
    }

    public sealed class EventInput
    {
        [Required(ErrorMessage = "Title is required")]
        [StringLength(200, ErrorMessage = "Title is too long")]
        public string Title { get; set; } = string.Empty;

        [StringLength(2000, ErrorMessage = "Description is too long")]
        public string? Description { get; set; }

        [Required(ErrorMessage = "Date and time is required")]
        public string StartsAt { get; set; } = string.Empty;

        [Required(ErrorMessage = "Location is required")]
        [StringLength(200, ErrorMessage = "Location is too long")]
        public string Location { get; set; } = string.Empty;

        [Range(1, 100000, ErrorMessage = "Capacity must be between 1 and 100000")]
        public int Capacity { get; set; } = 20;
    }
}
