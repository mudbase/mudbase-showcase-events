namespace MudbaseShowcase.Events.Models;

/// <summary>The five terminal outcomes of a check-in attempt - mirrors the reference app's `CheckInOutcome` union (../../web/src/hooks/useBookings.ts).</summary>
public enum CheckInOutcome
{
    CheckedIn,
    AlreadyCheckedIn,
    Cancelled,
    Waitlisted,
    NotFound,
}
