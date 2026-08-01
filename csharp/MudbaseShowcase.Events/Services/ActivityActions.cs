namespace MudbaseShowcase.Events.Services;

/// <summary>The fixed set of `action` string values this app writes to the "activity" collection - mirrors ../../web/src/types/activity.ts's `ActivityAction` union exactly.</summary>
public static class ActivityActions
{
    public const string BookingConfirmed = "booking_confirmed";
    public const string BookingWaitlisted = "booking_waitlisted";
    public const string BookingCancelled = "booking_cancelled";
    public const string BookingPromoted = "booking_promoted";
    public const string CheckedIn = "checked_in";
    public const string EventCreated = "event_created";
    public const string EventUpdated = "event_updated";
}
