using System.ComponentModel.DataAnnotations;
using System.Globalization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.Events.Models;
using MudbaseShowcase.Events.Services;

namespace MudbaseShowcase.Events.Pages.Events;

/// <summary>Organizer-only create-event form. Mirrors ../../../web/src/app/events/new/page.tsx + EventForm.tsx.</summary>
public sealed class NewModel : PageModel
{
    private readonly EventsService _events;
    private readonly ActivityService _activity;
    private readonly MudbaseSessionAccessor _session;

    public NewModel(EventsService events, ActivityService activity, MudbaseSessionAccessor session)
    {
        _events = events;
        _activity = activity;
        _session = session;
    }

    [BindProperty]
    public EventInput Input { get; set; } = new();

    public string? ErrorMessage { get; private set; }

    public IActionResult OnGet()
    {
        MudbaseSessionUser? user = _session.CurrentUser;
        if (user is null) return RedirectToPage("/Login");
        if (!Rbac.IsOrganizer(user.CustomRole)) return RedirectToPage("/Index");
        return Page();
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        MudbaseSessionUser? user = _session.CurrentUser;
        if (user is null) return RedirectToPage("/Login");
        if (!Rbac.IsOrganizer(user.CustomRole)) return RedirectToPage("/Index");

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
            EventDocument created = await _events.CreateAsync(
                Input.Title.Trim(),
                string.IsNullOrWhiteSpace(Input.Description) ? null : Input.Description.Trim(),
                startsAtUtc,
                Input.Location.Trim(),
                Input.Capacity,
                user.Id,
                user.DisplayName,
                cancellationToken);

            await _activity.LogAsync(created.Id, user.Id, user.DisplayName, ActivityActions.EventCreated, cancellationToken);

            return RedirectToPage("/Events/Detail", new { id = created.Id });
        }
        catch (MudbaseApiException ex)
        {
            ErrorMessage = "Couldn't create this event. (" + ex.Message + ")";
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
