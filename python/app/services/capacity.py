"""Python port of ../web/src/lib/capacity.ts::reconcileEventCapacity — read
that file's docstring first; this is a field-for-field port of the exact
same algorithm, not a reinterpretation.

Mudbase (a generic-CRUD BaaS) has no cross-document transactions or atomic
counters, so a plain "count confirmed, then create" is inherently racy: two
simultaneous booking requests can both read the same pre-write count and
both decide "there's room". This function narrows that race window by
re-deriving truth from a fresh read (creation-order priority: the first
`capacity` bookings, oldest first, among confirmed+waitlisted, are the ones
entitled to a seat) and correcting any booking that disagrees — whether
that means demoting an overshoot back to waitlisted, or promoting the
earliest waitlisted booking once a cancellation frees a seat.

Deliberately excludes `"checked_in"` bookings from the capacity count (see
../web/plan/build-plan.md "Capacity-Race Handling Approach") — the task's
spec defines capacity in terms of `"confirmed"` bookings specifically, and
running this after check-in would incorrectly free an already-seated
attendee's slot for someone else on the waitlist.

One deliberate deviation from the TypeScript original: that file fetches up
to `RECONCILE_FETCH_LIMIT = 1000` bookings per status, a ceiling that is
safe for a browser calling the raw REST API directly. This Python port goes
through the real Mudbase Python SDK, whose `DataApi.list_data` caps `limit`
at 100 server-side (a known platform constraint — see this build's task
brief, and the sibling mudbase-showcase-kanban/python port's
plan/build-plan.md for the live bug that resulted from missing it once
already) — so the fetch limit here is 100, not 1000. Fine for this demo
app's realistic event sizes; documented in plan/build-plan.md "Known
Limitations" as a real, load-bearing platform constraint, not an oversight.
"""

import asyncio
from datetime import datetime, timezone

from app.config import get_settings
from app.mudbase_client import list_data_sync, update_data_sync
from app.schemas.booking import BookingDoc
from app.services.activity import log_activity

_RECONCILE_FETCH_LIMIT = 100  # DataApi.list_data's server-enforced cap.
_EPOCH = datetime.min.replace(tzinfo=timezone.utc)


def _created_at_key(booking: BookingDoc) -> datetime:
    created_at = booking.created_at
    if created_at is None:
        return _EPOCH
    return created_at if created_at.tzinfo else created_at.replace(tzinfo=timezone.utc)


async def reconcile_event_capacity(event_id: str, capacity: int, *, access_token: str) -> None:
    settings = get_settings()

    confirmed_result, waitlisted_result = await asyncio.gather(
        asyncio.to_thread(
            list_data_sync,
            settings.bookings_collection_id,
            filter_dict={"eventId": event_id, "status": "confirmed"},
            sort="createdAt",
            limit=_RECONCILE_FETCH_LIMIT,
            access_token=access_token,
        ),
        asyncio.to_thread(
            list_data_sync,
            settings.bookings_collection_id,
            filter_dict={"eventId": event_id, "status": "waitlisted"},
            sort="createdAt",
            limit=_RECONCILE_FETCH_LIMIT,
            access_token=access_token,
        ),
    )

    confirmed = [BookingDoc.model_validate(doc) for doc in confirmed_result["data"]]
    waitlisted = [BookingDoc.model_validate(doc) for doc in waitlisted_result["data"]]
    live = sorted(confirmed + waitlisted, key=_created_at_key)

    corrections = []
    for index, booking in enumerate(live):
        should_be_confirmed = index < capacity
        if should_be_confirmed and booking.status != "confirmed":
            corrections.append(_promote(event_id, booking, access_token=access_token))
        elif not should_be_confirmed and booking.status != "waitlisted":
            corrections.append(_demote(event_id, booking, access_token=access_token))

    if corrections:
        await asyncio.gather(*corrections)


async def _promote(event_id: str, booking: BookingDoc, *, access_token: str) -> None:
    settings = get_settings()
    await asyncio.to_thread(
        update_data_sync, settings.bookings_collection_id, booking.id, {"status": "confirmed"}, access_token=access_token
    )
    await log_activity(
        event_id=event_id,
        actor_id=booking.user_id,
        actor_name=booking.user_name,
        action="booking_promoted",
        access_token=access_token,
    )


async def _demote(event_id: str, booking: BookingDoc, *, access_token: str) -> None:
    settings = get_settings()
    await asyncio.to_thread(
        update_data_sync, settings.bookings_collection_id, booking.id, {"status": "waitlisted"}, access_token=access_token
    )
    await log_activity(
        event_id=event_id,
        actor_id=booking.user_id,
        actor_name=booking.user_name,
        action="booking_waitlisted",
        access_token=access_token,
    )
