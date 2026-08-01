namespace MudbaseShowcase.Events.Models;

/// <summary>
/// One event plus its live confirmed-booking count, for the capacity indicator on its card/detail
/// view - mirrors the reference app's `useConfirmedCount` pairing with each `EventCard`
/// (../../web/src/components/events/EventCard.tsx). Resolved server-side before the page renders,
/// so - unlike the client-rendered reference app - there is no separate "count still loading"
/// state to model here.
/// </summary>
public sealed class EventListItemViewModel
{
    public required EventDocument Event { get; init; }
    public required int ConfirmedCount { get; init; }
}
