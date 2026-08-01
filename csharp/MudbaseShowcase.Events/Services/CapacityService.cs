using Microsoft.Extensions.Options;
using MudbaseShowcase.Events.Models;
using MudbaseShowcase.Events.Options;

namespace MudbaseShowcase.Events.Services;

/// <summary>
/// Direct port of ../../web/src/lib/capacity.ts's `reconcileEventCapacity` - re-derives which
/// bookings for an event should hold a confirmed seat versus sit on the waitlist, and patches only
/// the ones whose current status disagrees with that derivation.
///
/// Mudbase (a generic-CRUD BaaS) has no cross-document transactions or atomic counters, so a plain
/// "count confirmed, then create" is inherently racy: two simultaneous booking requests can both
/// read the same pre-write count and both decide "there's room". This narrows that race window by
/// re-deriving truth from a fresh read (creation-order priority: the first `capacity` bookings,
/// oldest first, among confirmed+waitlisted, are the ones entitled to a seat) and correcting any
/// booking that disagrees - whether that means demoting an overshoot back to waitlisted, or
/// promoting the earliest waitlisted booking once a cancellation frees a seat.
///
/// Deliberately excludes "checked_in" bookings from the capacity count (see
/// ../../web/plan/build-plan.md "Capacity-Race Handling Approach") - the task's spec defines
/// capacity in terms of `"confirmed"` bookings specifically, and running this after check-in would
/// incorrectly free an already-seated attendee's slot for someone else on the waitlist while they
/// are still present.
/// </summary>
public sealed class CapacityService
{
    // Generous ceiling on how many live (confirmed+waitlisted) bookings a single event can have
    // for reconciliation purposes - well beyond any capacity this demo app's create/edit-event
    // form allows, so it never truncates the real data.
    private const int ReconcileFetchLimit = 1000;

    private readonly MudbaseDataService _data;
    private readonly ActivityService _activity;
    private readonly MudbaseOptions _options;

    public CapacityService(MudbaseDataService data, ActivityService activity, IOptions<MudbaseOptions> options)
    {
        _data = data;
        _activity = activity;
        _options = options.Value;
    }

    public async Task ReconcileAsync(string eventId, int capacity, CancellationToken cancellationToken)
    {
        Task<MudbaseListResult<BookingDocument>> confirmedTask = _data.ListAsync<BookingDocument>(
            _options.BookingsCollectionId,
            new Dictionary<string, object?> { ["eventId"] = eventId, ["status"] = BookingStatus.Confirmed },
            sort: "createdAt",
            limit: ReconcileFetchLimit,
            cancellationToken: cancellationToken);

        Task<MudbaseListResult<BookingDocument>> waitlistedTask = _data.ListAsync<BookingDocument>(
            _options.BookingsCollectionId,
            new Dictionary<string, object?> { ["eventId"] = eventId, ["status"] = BookingStatus.Waitlisted },
            sort: "createdAt",
            limit: ReconcileFetchLimit,
            cancellationToken: cancellationToken);

        await Task.WhenAll(confirmedTask, waitlistedTask);

        List<BookingDocument> live = confirmedTask.Result.Items
            .Concat(waitlistedTask.Result.Items)
            .OrderBy(b => b.CreatedAt)
            .ToList();

        List<Task> corrections = new();

        for (int index = 0; index < live.Count; index++)
        {
            BookingDocument booking = live[index];
            bool shouldBeConfirmed = index < capacity;

            if (shouldBeConfirmed && booking.Status != BookingStatus.Confirmed)
            {
                corrections.Add(PromoteAsync(booking, eventId, cancellationToken));
            }
            else if (!shouldBeConfirmed && booking.Status != BookingStatus.Waitlisted)
            {
                corrections.Add(DemoteAsync(booking, eventId, cancellationToken));
            }
        }

        await Task.WhenAll(corrections);
    }

    private async Task PromoteAsync(BookingDocument booking, string eventId, CancellationToken cancellationToken)
    {
        await _data.UpdateAsync<BookingDocument>(
            _options.BookingsCollectionId, booking.Id, new Dictionary<string, object?> { ["status"] = BookingStatus.Confirmed }, cancellationToken);
        await _activity.LogAsync(eventId, booking.UserId, booking.UserName, ActivityActions.BookingPromoted, cancellationToken);
    }

    private async Task DemoteAsync(BookingDocument booking, string eventId, CancellationToken cancellationToken)
    {
        await _data.UpdateAsync<BookingDocument>(
            _options.BookingsCollectionId, booking.Id, new Dictionary<string, object?> { ["status"] = BookingStatus.Waitlisted }, cancellationToken);
        await _activity.LogAsync(eventId, booking.UserId, booking.UserName, ActivityActions.BookingWaitlisted, cancellationToken);
    }
}
