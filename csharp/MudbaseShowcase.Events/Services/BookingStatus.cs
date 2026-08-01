namespace MudbaseShowcase.Events.Services;

/// <summary>The fixed set of `status` string values a "bookings" document can hold - mirrors ../../web/src/types/booking.ts's `BookingStatus` union exactly.</summary>
public static class BookingStatus
{
    public const string Confirmed = "confirmed";
    public const string Waitlisted = "waitlisted";
    public const string Cancelled = "cancelled";
    public const string CheckedIn = "checked_in";
}
