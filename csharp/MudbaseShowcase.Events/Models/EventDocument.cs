using System.Text.Json.Serialization;

namespace MudbaseShowcase.Events.Models;

/// <summary>
/// Maps a document from the "events" Mudbase collection. Field names mirror the reference Next.js
/// implementation's `EventDoc` exactly (see ../../web/src/types/event.ts) so this is a faithful
/// port, not a reinterpretation.
/// </summary>
public sealed class EventDocument
{
    [JsonPropertyName("_id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("title")]
    public string Title { get; set; } = string.Empty;

    [JsonPropertyName("description")]
    public string? Description { get; set; }

    [JsonPropertyName("startsAt")]
    public DateTimeOffset StartsAt { get; set; }

    [JsonPropertyName("location")]
    public string Location { get; set; } = string.Empty;

    [JsonPropertyName("capacity")]
    public int Capacity { get; set; }

    [JsonPropertyName("organizerId")]
    public string OrganizerId { get; set; } = string.Empty;

    [JsonPropertyName("organizerName")]
    public string OrganizerName { get; set; } = string.Empty;

    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; set; }

    [JsonPropertyName("updatedAt")]
    public DateTimeOffset UpdatedAt { get; set; }
}
