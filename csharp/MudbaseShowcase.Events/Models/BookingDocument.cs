using System.Text.Json.Serialization;

namespace MudbaseShowcase.Events.Models;

/// <summary>
/// Maps a document from the "bookings" Mudbase collection. Field names mirror the reference
/// Next.js implementation's `BookingDoc` exactly (see ../../web/src/types/booking.ts). `Status`
/// is a plain string rather than an enum so it round-trips unmodified through
/// System.Text.Json - see Services/BookingStatus.cs for the fixed set of values this app reads
/// and writes.
/// </summary>
public sealed class BookingDocument
{
    [JsonPropertyName("_id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("eventId")]
    public string EventId { get; set; } = string.Empty;

    [JsonPropertyName("userId")]
    public string UserId { get; set; } = string.Empty;

    [JsonPropertyName("userName")]
    public string UserName { get; set; } = string.Empty;

    /// <summary>One of "confirmed" / "waitlisted" / "cancelled" / "checked_in" - see Services/BookingStatus.cs.</summary>
    [JsonPropertyName("status")]
    public string Status { get; set; } = string.Empty;

    [JsonPropertyName("qrToken")]
    public string QrToken { get; set; } = string.Empty;

    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; set; }

    [JsonPropertyName("updatedAt")]
    public DateTimeOffset UpdatedAt { get; set; }
}
