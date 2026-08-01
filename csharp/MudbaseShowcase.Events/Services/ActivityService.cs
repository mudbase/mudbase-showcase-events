using Microsoft.Extensions.Options;
using MudbaseShowcase.Events.Models;
using MudbaseShowcase.Events.Options;

namespace MudbaseShowcase.Events.Services;

/// <summary>Reads and appends to the "activity" collection - one event's audit/history feed. Direct port of ../../web/src/hooks/useActivity.ts's server calls.</summary>
public sealed class ActivityService
{
    private readonly MudbaseDataService _data;
    private readonly MudbaseOptions _options;

    public ActivityService(MudbaseDataService data, IOptions<MudbaseOptions> options)
    {
        _data = data;
        _options = options.Value;
    }

    /// <summary>Newest-first, paginated, scoped to one event.</summary>
    public Task<MudbaseListResult<ActivityDocument>> ListForEventAsync(string eventId, int page, int limit, CancellationToken cancellationToken) =>
        _data.ListAsync<ActivityDocument>(
            _options.ActivityCollectionId,
            new Dictionary<string, object?> { ["eventId"] = eventId },
            sort: "-createdAt",
            page: page,
            limit: limit,
            cancellationToken: cancellationToken);

    /// <summary>Appends one row.</summary>
    public Task<ActivityDocument> LogAsync(string eventId, string actorId, string actorName, string action, CancellationToken cancellationToken) =>
        _data.CreateAsync<ActivityDocument>(
            _options.ActivityCollectionId,
            new Dictionary<string, object?>
            {
                ["eventId"] = eventId,
                ["actorId"] = actorId,
                ["actorName"] = actorName,
                ["action"] = action,
            },
            cancellationToken);
}
