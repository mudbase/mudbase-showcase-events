"""bookings collection: both roles create/read their own bookings (Mudbase
collection permissions scope reads/writes to `userId === session.user.id`
for the attendee role; organizer bookings aren't modeled as a separate write
path in this UI — see ../web/plan/build-plan.md's RBAC matrix). Mirrors
../web/src/hooks/useBookings.ts field-for-field, including the exact
capacity-decide-then-reconcile approach documented there and ported in
`app/services/capacity.py`.
"""

import asyncio

from app.config import get_settings
from app.mudbase_client import get_data_sync, list_data_sync, update_data_sync
from app.mudbase_client import create_data_sync as _create_data_sync
from app.schemas.booking import BookingDoc
from app.services.activity import log_activity
from app.services.capacity import reconcile_event_capacity
from app.utils import generate_qr_token

_MY_BOOKINGS_LIMIT = 100  # DataApi.list_data's server-enforced cap.

CheckInOutcome = str  # "checked_in" | "already_checked_in" | "cancelled" | "waitlisted" | "not_found"


async def list_my_bookings(user_id: str, *, access_token: str) -> list[BookingDoc]:
    settings = get_settings()
    result = await asyncio.to_thread(
        list_data_sync,
        settings.bookings_collection_id,
        filter_dict={"userId": user_id},
        sort="-createdAt",
        limit=_MY_BOOKINGS_LIMIT,
        access_token=access_token,
    )
    return [BookingDoc.model_validate(doc) for doc in result["data"]]


async def get_booking_for_event(event_id: str, user_id: str, *, access_token: str) -> BookingDoc | None:
    """The signed-in user's own booking for one specific event, if any (used
    to hide the Book button / show its status instead — mirrors
    ../web/src/hooks/useBookings.ts::useMyBookingForEvent)."""
    settings = get_settings()
    result = await asyncio.to_thread(
        list_data_sync,
        settings.bookings_collection_id,
        filter_dict={"eventId": event_id, "userId": user_id},
        limit=1,
        access_token=access_token,
    )
    docs = result["data"]
    return BookingDoc.model_validate(docs[0]) if docs else None


async def get_booking(booking_id: str, *, access_token: str) -> BookingDoc | None:
    settings = get_settings()
    doc = await asyncio.to_thread(get_data_sync, settings.bookings_collection_id, booking_id, access_token=access_token)
    return BookingDoc.model_validate(doc) if doc else None


async def get_confirmed_count(event_id: str, *, access_token: str) -> int:
    """The live confirmed-booking count for one event, for the capacity
    indicator on its card/detail — mirrors
    ../web/src/hooks/useEvents.ts::useConfirmedCount (a real server-side
    count via `pagination.total`, not a client-cached guess)."""
    settings = get_settings()
    result = await asyncio.to_thread(
        list_data_sync,
        settings.bookings_collection_id,
        filter_dict={"eventId": event_id, "status": "confirmed"},
        limit=1,
        access_token=access_token,
    )
    pagination = result["pagination"] or {}
    total: int = pagination.get("total", 0)
    return total


async def create_booking(
    event_id: str,
    capacity: int,
    *,
    user_id: str,
    user_name: str,
    access_token: str,
) -> BookingDoc:
    """Mirrors ../web/src/hooks/useBookings.ts::useCreateBooking exactly:
    decide the initial status from a fresh server-side confirmed count,
    write it, log activity, run the shared reconciliation pass, then
    re-read the booking's *post-reconciliation* state so the caller never
    reports a status that got corrected out from under it a moment later."""
    settings = get_settings()
    confirmed_count = await get_confirmed_count(event_id, access_token=access_token)
    initial_status = "confirmed" if confirmed_count < capacity else "waitlisted"
    qr_token = generate_qr_token()

    created_doc = await asyncio.to_thread(
        _create_data_sync,
        settings.bookings_collection_id,
        {"eventId": event_id, "userId": user_id, "userName": user_name, "status": initial_status, "qrToken": qr_token},
        access_token=access_token,
    )
    booking = BookingDoc.model_validate(created_doc)

    await log_activity(
        event_id=event_id,
        actor_id=user_id,
        actor_name=user_name,
        action="booking_confirmed" if initial_status == "confirmed" else "booking_waitlisted",
        access_token=access_token,
    )

    await reconcile_event_capacity(event_id, capacity, access_token=access_token)

    refreshed = await asyncio.to_thread(
        get_data_sync, settings.bookings_collection_id, booking.id, access_token=access_token
    )
    return BookingDoc.model_validate(refreshed) if refreshed else booking


async def cancel_booking(booking: BookingDoc, capacity: int, *, access_token: str) -> None:
    """Mirrors ../web/src/hooks/useBookings.ts::useCancelBooking: cancels,
    logs activity, then reconciles so the earliest waitlisted booking is
    promoted into the freed seat."""
    settings = get_settings()
    await asyncio.to_thread(
        update_data_sync, settings.bookings_collection_id, booking.id, {"status": "cancelled"}, access_token=access_token
    )
    await log_activity(
        event_id=booking.event_id,
        actor_id=booking.user_id,
        actor_name=booking.user_name,
        action="booking_cancelled",
        access_token=access_token,
    )
    await reconcile_event_capacity(booking.event_id, capacity, access_token=access_token)


async def check_in_by_qr_token(
    event_id: str, qr_token: str, *, access_token: str
) -> tuple[CheckInOutcome, BookingDoc | None]:
    """Mirrors ../web/src/hooks/useBookings.ts::useCheckIn's outcome ladder
    exactly: not found, already checked in (idempotent), cancelled,
    waitlisted (cannot check in until promoted), or a fresh check-in."""
    settings = get_settings()
    trimmed = qr_token.strip()
    if not trimmed:
        return "not_found", None

    result = await asyncio.to_thread(
        list_data_sync,
        settings.bookings_collection_id,
        filter_dict={"eventId": event_id, "qrToken": trimmed},
        limit=1,
        access_token=access_token,
    )
    docs = result["data"]
    if not docs:
        return "not_found", None

    booking = BookingDoc.model_validate(docs[0])
    if booking.status == "checked_in":
        return "already_checked_in", booking
    if booking.status == "cancelled":
        return "cancelled", booking
    if booking.status == "waitlisted":
        return "waitlisted", booking

    updated_doc = await asyncio.to_thread(
        update_data_sync, settings.bookings_collection_id, booking.id, {"status": "checked_in"}, access_token=access_token
    )
    updated = BookingDoc.model_validate(updated_doc)
    await log_activity(
        event_id=event_id,
        actor_id=booking.user_id,
        actor_name=booking.user_name,
        action="checked_in",
        access_token=access_token,
    )
    return "checked_in", updated
