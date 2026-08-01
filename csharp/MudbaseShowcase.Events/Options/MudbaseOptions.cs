namespace MudbaseShowcase.Events.Options;

/// <summary>
/// Every config value this app needs to talk to a provisioned Mudbase project. Bound from the
/// "Mudbase" section of appsettings.json / environment variables - see appsettings.Example.json
/// at the repo root for the full list with descriptions. None of these values are secrets (a
/// project/collection id is not sensitive), so, unlike a real credential, they are checked into
/// appsettings.json directly - see README.md. Unlike the sibling Kanban port there is no single
/// shared "BoardId" here - this app is inherently multi-document (many events), each event's id
/// is a real Mudbase-issued ObjectId read back from the API, never a fixed config value.
/// </summary>
public sealed class MudbaseOptions
{
    public const string SectionName = "Mudbase";

    /// <summary>Mudbase API base URL. Defaults to the public cloud endpoint.</summary>
    public string BaseUrl { get; set; } = "https://cloud.mudbase.dev";

    /// <summary>The Mudbase project ID this app is provisioned against.</summary>
    public string ProjectId { get; set; } = string.Empty;

    /// <summary>Collection ID for the "events" collection.</summary>
    public string EventsCollectionId { get; set; } = string.Empty;

    /// <summary>Collection ID for the "bookings" collection.</summary>
    public string BookingsCollectionId { get; set; } = string.Empty;

    /// <summary>Collection ID for the "activity" collection (per-event audit feed).</summary>
    public string ActivityCollectionId { get; set; } = string.Empty;

    /// <summary>
    /// Throws with a clear, specific message if any required value was left unset, so a
    /// misconfigured deployment fails at startup instead of surfacing confusing errors deep
    /// inside a request handler.
    /// </summary>
    public void Validate()
    {
        var missing = new List<string>();

        if (string.IsNullOrWhiteSpace(BaseUrl)) missing.Add(nameof(BaseUrl));
        if (string.IsNullOrWhiteSpace(ProjectId)) missing.Add(nameof(ProjectId));
        if (string.IsNullOrWhiteSpace(EventsCollectionId)) missing.Add(nameof(EventsCollectionId));
        if (string.IsNullOrWhiteSpace(BookingsCollectionId)) missing.Add(nameof(BookingsCollectionId));
        if (string.IsNullOrWhiteSpace(ActivityCollectionId)) missing.Add(nameof(ActivityCollectionId));

        if (missing.Count > 0)
        {
            throw new InvalidOperationException(
                $"Missing required Mudbase configuration values: {string.Join(", ", missing)}. " +
                "Set them under the \"Mudbase\" section of appsettings.json, appsettings.Development.json, " +
                "or the corresponding Mudbase__<Key> environment variables. See appsettings.Example.json.");
        }
    }
}
