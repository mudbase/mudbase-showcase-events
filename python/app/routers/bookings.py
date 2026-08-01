"""Booking create/cancel, "My bookings", and QR-token check-in. Mirrors
../web/src/app/bookings/page.tsx, ../web/src/app/events/[id]/checkin/page.tsx,
and ../web/src/hooks/useBookings.ts.

Every mutating handler re-checks ownership (`booking.user_id == user.id` for
cancel; `event.organizer_id == user.id` for check-in) before calling a
service — this app's own defense-in-depth gate — but the real enforcement
boundary is Mudbase's own collection permissions.
"""

import asyncio
from typing import Annotated

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from app import rbac
from app.context import build_base_context
from app.mudbase_client import MudbaseApiError
from app.schemas.booking import BookingDoc
from app.schemas.event import EventDoc
from app.services import bookings as bookings_service
from app.services import events as events_service
from app.session import call_with_reauth, require_session, set_flash
from app.templates_env import templates

router = APIRouter()

def _checkin_message(outcome: str, name: str | None) -> str:
    """Mirrors ../web/src/components/bookings/CheckInForm.tsx::RESULT_COPY's
    per-outcome fallback names exactly, including the "This booking" fallback
    that reads oddly on `cancelled` — kept for fidelity with the reference
    copy rather than "corrected" into something that reads better."""
    if outcome == "checked_in":
        return f"{name or 'Guest'} is checked in."
    if outcome == "already_checked_in":
        return f"{name or 'This guest'} was already checked in."
    if outcome == "waitlisted":
        return f"{name or 'This guest'} is on the waitlist, not confirmed — cannot check in."
    if outcome == "cancelled":
        return f"{name or 'This booking'} was cancelled."
    return "No booking found for this code at this event."


@router.get("/bookings", response_class=HTMLResponse, response_model=None)
async def my_bookings_page(request: Request) -> HTMLResponse | RedirectResponse:
    gate = await require_session(request)
    if gate is None:
        return RedirectResponse("/login?next=/bookings", status_code=303)
    user, token = gate

    my_bookings: list[BookingDoc]
    events_by_id: dict[str, EventDoc]
    load_error: str | None
    try:
        my_bookings, token = await call_with_reauth(
            request, token, lambda t: bookings_service.list_my_bookings(user.id, access_token=t)
        )
        events_by_id = {}
        for event in await asyncio.gather(
            *(events_service.get_event(booking.event_id, access_token=token) for booking in my_bookings)
        ):
            if event is not None:
                events_by_id[event.id] = event
        load_error = None
    except MudbaseApiError as exc:
        my_bookings, events_by_id, load_error = [], {}, f"Couldn't load your bookings right now: {exc.message}"

    context = await build_base_context(request)
    context.update({"bookings": my_bookings, "events_by_id": events_by_id, "load_error": load_error})
    return templates.TemplateResponse(request=request, name="bookings.html", context=context)


@router.post("/events/{event_id}/book", response_model=None)
async def book_event_submit(request: Request, event_id: str) -> RedirectResponse:
    gate = await require_session(request)
    if gate is None:
        return RedirectResponse(f"/login?next=/events/{event_id}", status_code=303)
    user, token = gate

    event, token = await call_with_reauth(request, token, lambda t: events_service.get_event(event_id, access_token=t))
    if event is None:
        set_flash(request, "That event no longer exists.", "error")
        return RedirectResponse("/", status_code=303)
    if event.organizer_id == user.id:
        set_flash(request, "You can't book your own event.", "error")
        return RedirectResponse(f"/events/{event_id}", status_code=303)

    existing, token = await call_with_reauth(
        request, token, lambda t: bookings_service.get_booking_for_event(event_id, user.id, access_token=t)
    )
    if existing is not None and existing.status != "cancelled":
        set_flash(request, "You already have a booking for this event.", "info")
        return RedirectResponse(f"/events/{event_id}", status_code=303)

    try:
        booking, token = await call_with_reauth(
            request,
            token,
            lambda t: bookings_service.create_booking(
                event_id, event.capacity, user_id=user.id, user_name=user.display_name, access_token=t
            ),
        )
    except MudbaseApiError as exc:
        set_flash(request, f"Couldn't complete your booking: {exc.message}", "error")
        return RedirectResponse(f"/events/{event_id}", status_code=303)

    message = (
        "You're confirmed! See your ticket under My bookings."
        if booking.status == "confirmed"
        else "This event is full — you've been added to the waitlist."
    )
    set_flash(request, message, "success")
    return RedirectResponse(f"/events/{event_id}", status_code=303)


@router.post("/bookings/{booking_id}/cancel", response_model=None)
async def cancel_booking_submit(request: Request, booking_id: str) -> RedirectResponse:
    gate = await require_session(request)
    if gate is None:
        return RedirectResponse("/login?next=/bookings", status_code=303)
    user, token = gate

    booking, token = await call_with_reauth(
        request, token, lambda t: bookings_service.get_booking(booking_id, access_token=t)
    )
    if booking is None:
        set_flash(request, "That booking no longer exists.", "error")
        return RedirectResponse("/bookings", status_code=303)
    if booking.user_id != user.id:
        set_flash(request, "You can only cancel your own bookings.", "error")
        return RedirectResponse("/bookings", status_code=303)
    if booking.status not in ("confirmed", "waitlisted"):
        set_flash(request, "This booking can no longer be cancelled.", "info")
        return RedirectResponse("/bookings", status_code=303)

    event, token = await call_with_reauth(
        request, token, lambda t: events_service.get_event(booking.event_id, access_token=t)
    )
    if event is None:
        set_flash(request, "The event for this booking no longer exists.", "error")
        return RedirectResponse("/bookings", status_code=303)

    try:
        await call_with_reauth(
            request, token, lambda t: bookings_service.cancel_booking(booking, event.capacity, access_token=t)
        )
    except MudbaseApiError as exc:
        set_flash(request, f"Couldn't cancel this booking: {exc.message}", "error")
        return RedirectResponse("/bookings", status_code=303)

    set_flash(request, "Booking cancelled.", "success")
    return RedirectResponse("/bookings", status_code=303)


@router.get("/events/{event_id}/checkin", response_class=HTMLResponse, response_model=None)
async def checkin_page(request: Request, event_id: str) -> HTMLResponse | RedirectResponse:
    gate = await require_session(request)
    if gate is None:
        return RedirectResponse(f"/login?next=/events/{event_id}/checkin", status_code=303)
    user, token = gate

    event, token = await call_with_reauth(request, token, lambda t: events_service.get_event(event_id, access_token=t))
    if event is None:
        set_flash(request, "That event no longer exists.", "error")
        return RedirectResponse("/", status_code=303)
    if not rbac.is_organizer(user.custom_role) or event.organizer_id != user.id:
        set_flash(request, "Only this event's organizer can check guests in.", "error")
        return RedirectResponse(f"/events/{event_id}", status_code=303)

    context = await build_base_context(request)
    context.update({"event": event, "result_message": None, "result_category": None})
    return templates.TemplateResponse(request=request, name="checkin.html", context=context)


@router.post("/events/{event_id}/checkin", response_class=HTMLResponse, response_model=None)
async def checkin_submit(
    request: Request, event_id: str, qr_token: Annotated[str, Form()]
) -> HTMLResponse | RedirectResponse:
    gate = await require_session(request)
    if gate is None:
        return RedirectResponse(f"/login?next=/events/{event_id}/checkin", status_code=303)
    user, token = gate

    event, token = await call_with_reauth(request, token, lambda t: events_service.get_event(event_id, access_token=t))
    if event is None:
        set_flash(request, "That event no longer exists.", "error")
        return RedirectResponse("/", status_code=303)
    if not rbac.is_organizer(user.custom_role) or event.organizer_id != user.id:
        set_flash(request, "Only this event's organizer can check guests in.", "error")
        return RedirectResponse(f"/events/{event_id}", status_code=303)

    try:
        (outcome, booking), token = await call_with_reauth(
            request, token, lambda t: bookings_service.check_in_by_qr_token(event_id, qr_token, access_token=t)
        )
    except MudbaseApiError as exc:
        context = await build_base_context(request)
        context.update({"event": event, "result_message": exc.message, "result_category": "error"})
        return templates.TemplateResponse(request=request, name="checkin.html", context=context, status_code=502)

    name = booking.user_name if booking else None
    message = _checkin_message(outcome, name)
    category = "success" if outcome == "checked_in" else ("info" if outcome in ("already_checked_in", "waitlisted") else "error")

    context = await build_base_context(request)
    context.update({"event": event, "result_message": message, "result_category": category})
    return templates.TemplateResponse(request=request, name="checkin.html", context=context)
