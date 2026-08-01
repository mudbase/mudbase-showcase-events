using System.Text.Json.Serialization;

namespace MudbaseShowcase.Events.Models;

/// <summary>
/// Maps a document from the "activity" Mudbase collection - a per-event audit/history feed
/// (unlike the sibling Kanban port's board-wide feed, every row here is scoped to one `eventId`).
/// See Services/ActivityActions.cs for the fixed set of `Action` values this app writes, and
/// Services/ActivityLabels.cs for rendering one row as a readable sentence fragment.
/// </summary>
public sealed class ActivityDocument
{
    [JsonPropertyName("_id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("eventId")]
    public string EventId { get; set; } = string.Empty;

    [JsonPropertyName("actorId")]
    public string ActorId { get; set; } = string.Empty;

    [JsonPropertyName("actorName")]
    public string ActorName { get; set; } = string.Empty;

    [JsonPropertyName("action")]
    public string Action { get; set; } = string.Empty;

    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; set; }

    [JsonPropertyName("updatedAt")]
    public DateTimeOffset UpdatedAt { get; set; }
}
