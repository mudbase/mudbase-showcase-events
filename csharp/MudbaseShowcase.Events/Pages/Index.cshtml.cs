using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.Events.Models;
using MudbaseShowcase.Events.Services;

namespace MudbaseShowcase.Events.Pages;

/// <summary>
/// The event list: paginated, soonest-first, each card showing a live confirmed-vs-capacity
/// indicator. Mirrors ../../web/src/app/page.tsx + EventList.tsx/EventCard.tsx. The
/// "sign in to see upcoming events" hero the reference client-rendered app shows to signed-out
/// visitors has no equivalent here - RequireMudbaseSessionMiddleware already redirects every
/// unauthenticated request to /Login before this page ever renders (the server-side equivalent of
/// that same AuthGate), exactly as the sibling Kanban port's Index page assumes.
/// </summary>
public sealed class IndexModel : PageModel
{
    private const int PageSize = 10;

    private readonly EventsService _events;
    private readonly MudbaseSessionAccessor _session;

    public IndexModel(EventsService events, MudbaseSessionAccessor session)
    {
        _events = events;
        _session = session;
    }

    public IReadOnlyList<EventListItemViewModel> Events { get; private set; } = Array.Empty<EventListItemViewModel>();

    public int CurrentPage { get; private set; } = 1;

    public int TotalPages { get; private set; } = 1;

    public bool HasMore { get; private set; }

    public string? LoadError { get; private set; }

    public bool IsOrganizerFlag => Rbac.IsOrganizer(_session.CurrentUser?.CustomRole);

    // NOTE: the query/route parameter is deliberately "pg", not "page" - Razor Pages reserves the
    // route-value key "page" internally for ambient self-redirects. Reusing "page" for pagination
    // here would silently corrupt that ambient value (a live-verified failure mode from the
    // sibling social showcase's port, carried forward as a fixed convention across every C# port
    // in this family).
    public async Task OnGetAsync(int? pg, CancellationToken cancellationToken)
    {
        CurrentPage = pg is > 0 ? pg.Value : 1;

        try
        {
            MudbaseListResult<EventDocument> result = await _events.ListAsync(CurrentPage, PageSize, cancellationToken);

            EventListItemViewModel[] withCounts = await Task.WhenAll(result.Items.Select(async e => new EventListItemViewModel
            {
                Event = e,
                ConfirmedCount = await _events.ConfirmedCountAsync(e.Id, cancellationToken),
            }));

            Events = withCounts;
            TotalPages = result.TotalPages;
            HasMore = CurrentPage < result.TotalPages;
        }
        catch (MudbaseApiException ex)
        {
            LoadError = "Couldn't load events right now. (" + ex.Message + ")";
        }
    }
}
