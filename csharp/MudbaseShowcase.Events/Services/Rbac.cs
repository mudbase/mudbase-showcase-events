namespace MudbaseShowcase.Events.Services;

/// <summary>
/// Client-/server-side mirror of the RBAC matrix Mudbase's own collection permissions already
/// enforce server-side on the real project (see plan/build-plan.md). Used both to hide/disable
/// controls a role cannot use in the Razor views, and as a second, server-side check inside every
/// mutating Razor Page handler before ever calling Mudbase - it is NOT the real security boundary
/// by itself. A raw API call bypassing this app's UI entirely is still rejected by the platform;
/// see the reference app's plan/build-plan.md "Live Smoke Test Results" (../../web/plan/build-plan.md),
/// carried forward here since both ports share the same live project/collections/roles.
///
/// Booking creation is deliberately NOT gated here: per the reference app's RBAC matrix, an
/// organizer may book another organizer's event (only their own event's Book affordance is
/// hidden, an ownership check, not a role check) - see Pages/Events/Detail.cshtml.cs.
/// </summary>
public static class Rbac
{
    public const string Organizer = "organizer";
    public const string Attendee = "attendee";

    public static bool IsOrganizer(string? role) => role == Organizer;

    public static bool IsAttendee(string? role) => role == Attendee;

    public static string RoleLabel(string? role) => role switch
    {
        Organizer => "Organizer",
        Attendee => "Attendee",
        _ => "Unknown",
    };
}
