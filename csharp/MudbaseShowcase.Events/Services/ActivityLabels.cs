namespace MudbaseShowcase.Events.Services;

/// <summary>Renders one activity row's `action` as a short label fragment for the feed - direct port of ../../web/src/types/activity.ts's `ACTIVITY_LABELS`.</summary>
public static class ActivityLabels
{
    private static readonly IReadOnlyDictionary<string, string> Labels = new Dictionary<string, string>
    {
        [ActivityActions.BookingConfirmed] = "booked (confirmed)",
        [ActivityActions.BookingWaitlisted] = "joined the waitlist",
        [ActivityActions.BookingCancelled] = "cancelled their booking",
        [ActivityActions.BookingPromoted] = "was promoted from the waitlist",
        [ActivityActions.CheckedIn] = "checked in",
        [ActivityActions.EventCreated] = "created this event",
        [ActivityActions.EventUpdated] = "updated this event",
    };

    public static string Describe(string action) => Labels.TryGetValue(action, out string? label) ? label : "did something on this event";
}
