using System.Globalization;

namespace MudbaseShowcase.Events.Services;

/// <summary>Small display-formatting helpers shared by Razor views. Mirrors ../../web/src/lib/utils.ts and ../../web/src/components/events/CapacityBadge.tsx.</summary>
public static class DisplayHelpers
{
    /// <summary>Mirrors formatRelativeTime - used for activity feed timestamps.</summary>
    public static string FormatRelativeTime(DateTimeOffset value)
    {
        double seconds = (DateTimeOffset.UtcNow - value).TotalSeconds;

        if (seconds < 5) return "just now";
        if (seconds < 60) return $"{(int)seconds}s";

        double minutes = Math.Round(seconds / 60);
        if (minutes < 60) return $"{(int)minutes}m";

        double hours = Math.Round(minutes / 60);
        if (hours < 24) return $"{(int)hours}h";

        double days = Math.Round(hours / 24);
        if (days < 7) return $"{(int)days}d";

        return value.ToLocalTime().ToString("MMM d, yyyy", CultureInfo.InvariantCulture);
    }

    /// <summary>Mirrors formatDateTime - "medium date, short time" style, e.g. "Aug 1, 2026, 3:45 PM".</summary>
    public static string FormatDateTime(DateTimeOffset value) =>
        value.ToLocalTime().ToString("MMM d, yyyy, h:mm tt", CultureInfo.InvariantCulture);

    /// <summary>
    /// Mirrors toDateTimeLocalValue - the value an `&lt;input type="datetime-local"&gt;` expects
    /// (local time, no timezone/seconds), for pre-filling the edit-event form.
    /// </summary>
    public static string ToDateTimeLocalValue(DateTimeOffset value) =>
        value.ToLocalTime().ToString("yyyy-MM-ddTHH:mm", CultureInfo.InvariantCulture);

    /// <summary>
    /// Mirrors CapacityBadge.tsx's variant/label derivation exactly: full once remaining hits
    /// zero, a warning once remaining is down to the greater of 1 or 10% of capacity, success
    /// otherwise.
    /// </summary>
    public static (string Label, string BadgeCssClass) CapacityBadge(int confirmed, int capacity)
    {
        int remaining = capacity - confirmed;
        int warningThreshold = Math.Max(1, (int)Math.Ceiling(capacity * 0.1));

        string badgeCssClass = remaining <= 0
            ? "text-bg-danger"
            : remaining <= warningThreshold
                ? "text-bg-warning"
                : "text-bg-success";

        string label = remaining <= 0 ? $"Full · {confirmed}/{capacity}" : $"{confirmed}/{capacity} booked";

        return (label, badgeCssClass);
    }
}
