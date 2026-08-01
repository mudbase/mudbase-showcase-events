using Microsoft.Extensions.Options;
using MudbaseShowcase.Events.Models;
using MudbaseShowcase.Events.Options;

namespace MudbaseShowcase.Events.Services;

/// <summary>
/// Booking create/cancel/check-in - direct port of ../../web/src/hooks/useBookings.ts's server
/// calls. Every write here is followed by an activity log entry and, for create/cancel, a
/// <see cref="CapacityService.ReconcileAsync"/> pass so a race against another concurrent booking
/// self-corrects (see CapacityService.cs's doc comment and ../../web/plan/build-plan.md).
/// </summary>
public sealed class BookingsService
{
    private readonly MudbaseDataService _data;
    private readonly ActivityService _activity;
    private readonly CapacityService _capacity;
    private readonly MudbaseOptions _options;

    public BookingsService(MudbaseDataService data, ActivityService activity, CapacityService capacity, IOptions<MudbaseOptions> options)
    {
        _data = data;
        _activity = activity;
        _capacity = capacity;
        _options = options.Value;
    }

    /// <summary>The signed-in user's own bookings across every event, newest first.</summary>
    public Task<MudbaseListResult<BookingDocument>> ListForUserAsync(string userId, CancellationToken cancellationToken) =>
        _data.ListAsync<BookingDocument>(
            _options.BookingsCollectionId,
            new Dictionary<string, object?> { ["userId"] = userId },
            sort: "-createdAt",
            limit: 100,
            cancellationToken: cancellationToken);

    /// <summary>
    /// Fetches a single booking by id - used by <see cref="Pages.BookingsModel.OnPostCancelAsync"/>
    /// to independently re-derive `eventId`/ownership server-side instead of trusting posted hidden
    /// form fields (a client can tamper `eventId`/`capacity` on any form; `bookingId` alone is not
    /// enough to authorize a cancel without also checking `UserId` against the caller).
    /// </summary>
    public Task<BookingDocument?> GetAsync(string bookingId, CancellationToken cancellationToken) =>
        _data.GetAsync<BookingDocument>(_options.BookingsCollectionId, bookingId, cancellationToken);

    /// <summary>
    /// The signed-in user's own active (non-cancelled) booking for one event, if any - used to
    /// decide whether to show a Book button or an existing-booking status badge. Mirrors
    /// useMyBookingForEvent's `{ filter: { eventId, userId }, limit: 1 }` query, then the same
    /// client-side `find(b =&gt; b.status !== "cancelled")` the reference app's BookButton applies.
    /// </summary>
    public async Task<BookingDocument?> GetActiveBookingAsync(string eventId, string userId, CancellationToken cancellationToken)
    {
        MudbaseListResult<BookingDocument> result = await _data.ListAsync<BookingDocument>(
            _options.BookingsCollectionId,
            new Dictionary<string, object?> { ["eventId"] = eventId, ["userId"] = userId },
            limit: 1,
            cancellationToken: cancellationToken);
        return result.Items.FirstOrDefault(b => b.Status != BookingStatus.Cancelled);
    }

    /// <summary>
    /// Creates a booking using the capacity-race approach documented in
    /// ../../web/plan/build-plan.md: decide the initial status from a fresh server-side confirmed
    /// count, write it, then run the shared reconciliation pass so a race against another
    /// concurrent booking self-corrects. Returns the booking's *post-reconciliation* state, not
    /// its tentative initial write, so the caller never reports a status that got corrected out
    /// from under it a moment later.
    /// </summary>
    public async Task<BookingDocument> CreateAsync(string eventId, int capacity, string userId, string userName, CancellationToken cancellationToken)
    {
        MudbaseListResult<BookingDocument> confirmedResult = await _data.ListAsync<BookingDocument>(
            _options.BookingsCollectionId,
            new Dictionary<string, object?> { ["eventId"] = eventId, ["status"] = BookingStatus.Confirmed },
            limit: 1,
            cancellationToken: cancellationToken);

        string initialStatus = confirmedResult.Total < capacity ? BookingStatus.Confirmed : BookingStatus.Waitlisted;
        string qrToken = QrTokenGenerator.Generate();

        BookingDocument booking = await _data.CreateAsync<BookingDocument>(
            _options.BookingsCollectionId,
            new Dictionary<string, object?>
            {
                ["eventId"] = eventId,
                ["userId"] = userId,
                ["userName"] = userName,
                ["status"] = initialStatus,
                ["qrToken"] = qrToken,
            },
            cancellationToken);

        await _activity.LogAsync(
            eventId, userId, userName,
            initialStatus == BookingStatus.Confirmed ? ActivityActions.BookingConfirmed : ActivityActions.BookingWaitlisted,
            cancellationToken);

        await _capacity.ReconcileAsync(eventId, capacity, cancellationToken);

        // Re-read: reconciliation above may have demoted this exact booking if it lost a race
        // against another concurrent request that also decided "confirmed" from the same
        // pre-write count.
        return (await _data.GetAsync<BookingDocument>(_options.BookingsCollectionId, booking.Id, cancellationToken))!;
    }

    /// <summary>Cancels an attendee's own booking, then reconciles so the earliest waitlisted booking is promoted into the freed seat.</summary>
    public async Task CancelAsync(string bookingId, string eventId, int capacity, string userId, string userName, CancellationToken cancellationToken)
    {
        await _data.UpdateAsync<BookingDocument>(
            _options.BookingsCollectionId, bookingId, new Dictionary<string, object?> { ["status"] = BookingStatus.Cancelled }, cancellationToken);

        await _activity.LogAsync(eventId, userId, userName, ActivityActions.BookingCancelled, cancellationToken);

        await _capacity.ReconcileAsync(eventId, capacity, cancellationToken);
    }

    /// <summary>Looks up a booking by its scanned/pasted qrToken within one event and, if eligible, checks it in.</summary>
    public async Task<CheckInResult> CheckInAsync(string eventId, string qrToken, CancellationToken cancellationToken)
    {
        string trimmed = qrToken.Trim();
        if (trimmed.Length == 0)
        {
            return new CheckInResult { Outcome = CheckInOutcome.NotFound };
        }

        MudbaseListResult<BookingDocument> result = await _data.ListAsync<BookingDocument>(
            _options.BookingsCollectionId,
            new Dictionary<string, object?> { ["eventId"] = eventId, ["qrToken"] = trimmed },
            limit: 1,
            cancellationToken: cancellationToken);

        BookingDocument? booking = result.Items.FirstOrDefault();
        if (booking is null)
        {
            return new CheckInResult { Outcome = CheckInOutcome.NotFound };
        }

        if (booking.Status == BookingStatus.CheckedIn)
        {
            return new CheckInResult { Outcome = CheckInOutcome.AlreadyCheckedIn, Booking = booking };
        }

        if (booking.Status == BookingStatus.Cancelled)
        {
            return new CheckInResult { Outcome = CheckInOutcome.Cancelled, Booking = booking };
        }

        if (booking.Status == BookingStatus.Waitlisted)
        {
            return new CheckInResult { Outcome = CheckInOutcome.Waitlisted, Booking = booking };
        }

        BookingDocument updated = await _data.UpdateAsync<BookingDocument>(
            _options.BookingsCollectionId, booking.Id, new Dictionary<string, object?> { ["status"] = BookingStatus.CheckedIn }, cancellationToken);

        await _activity.LogAsync(eventId, booking.UserId, booking.UserName, ActivityActions.CheckedIn, cancellationToken);

        return new CheckInResult { Outcome = CheckInOutcome.CheckedIn, Booking = updated };
    }
}
