using Microsoft.Extensions.Options;
using MudbaseShowcase.Events.Models;
using MudbaseShowcase.Events.Options;

namespace MudbaseShowcase.Events.Services;

/// <summary>Event CRUD plus the live confirmed-booking count - direct port of ../../web/src/hooks/useEvents.ts's server calls. Create/update/delete are organizer-only, enforced both defensively in the Razor Page handlers (via <see cref="Rbac"/>) and by Mudbase's own collection permissions.</summary>
public sealed class EventsService
{
    private readonly MudbaseDataService _data;
    private readonly MudbaseOptions _options;

    public EventsService(MudbaseDataService data, IOptions<MudbaseOptions> options)
    {
        _data = data;
        _options = options.Value;
    }

    /// <summary>Soonest-first, paginated - mirrors useEvents's `sort: "startsAt"`.</summary>
    public Task<MudbaseListResult<EventDocument>> ListAsync(int page, int limit, CancellationToken cancellationToken) =>
        _data.ListAsync<EventDocument>(_options.EventsCollectionId, filter: null, sort: "startsAt", page: page, limit: limit, cancellationToken: cancellationToken);

    public Task<EventDocument?> GetAsync(string eventId, CancellationToken cancellationToken) =>
        _data.GetAsync<EventDocument>(_options.EventsCollectionId, eventId, cancellationToken);

    public Task<EventDocument> CreateAsync(
        string title, string? description, DateTimeOffset startsAt, string location, int capacity,
        string organizerId, string organizerName, CancellationToken cancellationToken)
    {
        var data = new Dictionary<string, object?>
        {
            ["title"] = title,
            ["startsAt"] = ToIso8601(startsAt),
            ["location"] = location,
            ["capacity"] = capacity,
            ["organizerId"] = organizerId,
            ["organizerName"] = organizerName,
        };

        if (!string.IsNullOrWhiteSpace(description))
        {
            data["description"] = description;
        }

        return _data.CreateAsync<EventDocument>(_options.EventsCollectionId, data, cancellationToken);
    }

    public Task<EventDocument> UpdateAsync(
        string eventId, string title, string? description, DateTimeOffset startsAt, string location, int capacity,
        CancellationToken cancellationToken)
    {
        var data = new Dictionary<string, object?>
        {
            ["title"] = title,
            ["description"] = description ?? string.Empty,
            ["startsAt"] = ToIso8601(startsAt),
            ["location"] = location,
            ["capacity"] = capacity,
        };

        return _data.UpdateAsync<EventDocument>(_options.EventsCollectionId, eventId, data, cancellationToken);
    }

    /// <summary>
    /// Matches JavaScript's `Date.prototype.toISOString()` output exactly (millisecond precision,
    /// `Z` suffix) rather than .NET's round-trip `"O"` format (which would emit `+00:00`) - the
    /// reference app writes `new Date(values.startsAt).toISOString()` for this same field, and
    /// this port's write should be byte-for-byte identical rather than merely "a valid ISO 8601
    /// string", in case Mudbase or any other port's reader is stricter than the spec requires.
    /// </summary>
    private static string ToIso8601(DateTimeOffset value) =>
        value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", System.Globalization.CultureInfo.InvariantCulture);

    public Task DeleteAsync(string eventId, CancellationToken cancellationToken) =>
        _data.DeleteAsync(_options.EventsCollectionId, eventId, cancellationToken);

    /// <summary>
    /// The live confirmed-booking count for one event, for the capacity indicator on its
    /// card/detail view - mirrors useConfirmedCount's `pagination.total` read against a
    /// `limit: 1` query (the count comes from the server-side pagination metadata, not from
    /// counting the returned page).
    /// </summary>
    public async Task<int> ConfirmedCountAsync(string eventId, CancellationToken cancellationToken)
    {
        MudbaseListResult<BookingDocument> result = await _data.ListAsync<BookingDocument>(
            _options.BookingsCollectionId,
            new Dictionary<string, object?> { ["eventId"] = eventId, ["status"] = BookingStatus.Confirmed },
            limit: 1,
            cancellationToken: cancellationToken);
        return result.Total;
    }
}
