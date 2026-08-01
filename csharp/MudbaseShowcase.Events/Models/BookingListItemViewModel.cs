namespace MudbaseShowcase.Events.Models;

/// <summary>
/// One of the signed-in user's own bookings, joined against its event (title/date/location) -
/// mirrors the reference app's `useEventsByIds` join pattern
/// (../../web/src/hooks/useEvents.ts) used by the `/bookings` page, since a generic-CRUD BaaS has
/// no native cross-collection join. `Event` is null if the event was deleted after the booking
/// was made.
/// </summary>
public sealed class BookingListItemViewModel
{
    public required BookingDocument Booking { get; init; }
    public EventDocument? Event { get; init; }
}
