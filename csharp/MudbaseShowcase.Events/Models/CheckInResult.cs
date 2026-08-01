namespace MudbaseShowcase.Events.Models;

/// <summary>The result of one check-in attempt - mirrors the reference app's `CheckInResult` (../../web/src/hooks/useBookings.ts). `Booking` is populated for every outcome except NotFound.</summary>
public sealed class CheckInResult
{
    public required CheckInOutcome Outcome { get; init; }
    public BookingDocument? Booking { get; init; }
}
