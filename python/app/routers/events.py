"""Event list/detail/create/edit/delete. Mirrors ../web/src/app/page.tsx,
../web/src/app/events/new/page.tsx, ../web/src/app/events/[id]/page.tsx,
and ../web/src/app/events/[id]/edit/page.tsx.

Every mutating handler re-checks `app.rbac` plus an inline
`organizer_id == user.id` ownership check before calling a service — this
app's own defense-in-depth gate — but the real enforcement boundary is
Mudbase's own collection permissions.
"""

import asyncio
import logging
from typing import Annotated

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import ValidationError

from app import rbac
from app.context import build_base_context
from app.mudbase_client import MudbaseApiError
from app.schemas.activity import ACTIVITY_LABELS, ActivityEntry
from app.schemas.booking import BookingDoc
from app.schemas.event import EventDoc, EventFormValues, starts_at_local_value
from app.schemas.pagination import PaginationMeta
from app.services import bookings as bookings_service
from app.services import events as events_service
from app.services.activity import list_event_activity, log_activity
from app.session import SessionUser, call_with_reauth, require_session, set_flash
from app.templates_env import templates

router = APIRouter()
logger = logging.getLogger(__name__)


def _actor_fields(user: SessionUser) -> tuple[str, str]:
    return user.id, user.display_name


@router.get("/", response_class=HTMLResponse, response_model=None)
async def home_index(request: Request, page: int = 1) -> HTMLResponse:
    """Unlike every other page in this app, an unauthenticated visitor sees an
    inline sign-in prompt here rather than a redirect — mirrors
    ../web/src/app/page.tsx's own behavior exactly (this project has no
    public/anonymous role, so there is nothing to show them but a prompt)."""
    gate = await require_session(request)
    context = await build_base_context(request)

    if gate is None:
        return templates.TemplateResponse(request=request, name="index.html", context={**context, "events": None})

    user, token = gate
    safe_page = max(1, page)

    events: list[EventDoc]
    pagination: PaginationMeta | None
    confirmed_counts: list[int]
    load_error: str | None
    try:
        (events, pagination), token = await call_with_reauth(
            request, token, lambda t: events_service.list_events(page=safe_page, access_token=t)
        )
        confirmed_counts = await asyncio.gather(
            *(bookings_service.get_confirmed_count(event.id, access_token=token) for event in events)
        )
        load_error = None
    except MudbaseApiError as exc:
        events, pagination, confirmed_counts, load_error = [], None, [], f"Couldn't load events right now: {exc.message}"

    event_rows = list(zip(events, confirmed_counts, strict=True))

    context.update(
        {
            "events": event_rows,
            "pagination": pagination,
            "page": safe_page,
            "load_error": load_error,
        }
    )
    return templates.TemplateResponse(request=request, name="index.html", context=context)


@router.get("/events/new", response_class=HTMLResponse, response_model=None)
async def new_event_page(request: Request) -> HTMLResponse | RedirectResponse:
    gate = await require_session(request)
    if gate is None:
        return RedirectResponse("/login?next=/events/new", status_code=303)
    user, _token = gate
    if not rbac.is_organizer(user.custom_role):
        set_flash(request, "Only organizers can create events.", "error")
        return RedirectResponse("/", status_code=303)

    context = await build_base_context(request)
    context.update({"errors": {}, "form_error": None, "event": None})
    return templates.TemplateResponse(request=request, name="event_form.html", context=context)


@router.post("/events", response_model=None)
async def create_event_submit(
    request: Request,
    title: Annotated[str, Form()],
    starts_at: Annotated[str, Form()],
    location: Annotated[str, Form()],
    capacity: Annotated[int, Form()],
    description: Annotated[str, Form()] = "",
) -> HTMLResponse | RedirectResponse:
    gate = await require_session(request)
    if gate is None:
        return RedirectResponse("/login?next=/events/new", status_code=303)
    user, token = gate
    if not rbac.is_organizer(user.custom_role):
        set_flash(request, "Only organizers can create events.", "error")
        return RedirectResponse("/", status_code=303)

    try:
        values = EventFormValues(title=title, description=description, starts_at=starts_at, location=location, capacity=capacity)
    except ValidationError as exc:
        context = await build_base_context(request)
        context.update({"errors": _field_errors(exc), "form_error": None, "event": None})
        return templates.TemplateResponse(request=request, name="event_form.html", context=context, status_code=422)

    actor_id, actor_name = _actor_fields(user)
    try:
        created, token = await call_with_reauth(
            request,
            token,
            lambda t: events_service.create_event(values, organizer_id=actor_id, organizer_name=actor_name, access_token=t),
        )
        await call_with_reauth(
            request,
            token,
            lambda t: log_activity(event_id=created.id, actor_id=actor_id, actor_name=actor_name, action="event_created", access_token=t),
        )
    except MudbaseApiError as exc:
        context = await build_base_context(request)
        context.update({"errors": {}, "form_error": exc.message, "event": None})
        return templates.TemplateResponse(request=request, name="event_form.html", context=context, status_code=400)

    set_flash(request, "Event created.", "success")
    return RedirectResponse(f"/events/{created.id}", status_code=303)


@router.get("/events/{event_id}", response_class=HTMLResponse, response_model=None)
async def event_detail(request: Request, event_id: str) -> HTMLResponse | RedirectResponse:
    gate = await require_session(request)
    if gate is None:
        return RedirectResponse(f"/login?next=/events/{event_id}", status_code=303)
    user, token = gate

    try:
        event, token = await call_with_reauth(request, token, lambda t: events_service.get_event(event_id, access_token=t))
    except MudbaseApiError as exc:
        context = await build_base_context(request)
        context.update({"event": None, "load_error": f"Couldn't load this event: {exc.message}"})
        return templates.TemplateResponse(request=request, name="event_detail.html", context=context, status_code=502)

    if event is None:
        context = await build_base_context(request)
        context.update({"event": None, "load_error": "Event not found."})
        return templates.TemplateResponse(request=request, name="event_detail.html", context=context, status_code=404)

    is_owner = event.organizer_id == user.id

    confirmed_count: int
    my_booking: BookingDoc | None
    activity: list[ActivityEntry]
    load_error: str | None
    try:
        confirmed_count, token = await call_with_reauth(
            request, token, lambda t: bookings_service.get_confirmed_count(event.id, access_token=t)
        )
        my_booking, token = await call_with_reauth(
            request, token, lambda t: bookings_service.get_booking_for_event(event.id, user.id, access_token=t)
        )
        activity, token = await call_with_reauth(
            request, token, lambda t: list_event_activity(event.id, access_token=t)
        )
        load_error = None
    except MudbaseApiError as exc:
        confirmed_count, my_booking, activity, load_error = 0, None, [], f"Couldn't load event details: {exc.message}"

    context = await build_base_context(request)
    context.update(
        {
            "event": event,
            "is_owner": is_owner,
            "confirmed_count": confirmed_count,
            "my_booking": my_booking,
            "activity": activity,
            "activity_labels": ACTIVITY_LABELS,
            "load_error": load_error,
        }
    )
    return templates.TemplateResponse(request=request, name="event_detail.html", context=context)


@router.get("/events/{event_id}/edit", response_class=HTMLResponse, response_model=None)
async def edit_event_page(request: Request, event_id: str) -> HTMLResponse | RedirectResponse:
    gate = await require_session(request)
    if gate is None:
        return RedirectResponse(f"/login?next=/events/{event_id}/edit", status_code=303)
    user, token = gate

    event, token = await call_with_reauth(request, token, lambda t: events_service.get_event(event_id, access_token=t))
    if event is None:
        set_flash(request, "That event no longer exists.", "error")
        return RedirectResponse("/", status_code=303)
    if not rbac.is_organizer(user.custom_role) or event.organizer_id != user.id:
        set_flash(request, "Only this event's organizer can edit it.", "error")
        return RedirectResponse(f"/events/{event_id}", status_code=303)

    context = await build_base_context(request)
    context.update(
        {
            "errors": {},
            "form_error": None,
            "event": event,
            "starts_at_value": starts_at_local_value(event.starts_at),
        }
    )
    return templates.TemplateResponse(request=request, name="event_form.html", context=context)


@router.post("/events/{event_id}/edit", response_model=None)
async def edit_event_submit(
    request: Request,
    event_id: str,
    title: Annotated[str, Form()],
    starts_at: Annotated[str, Form()],
    location: Annotated[str, Form()],
    capacity: Annotated[int, Form()],
    description: Annotated[str, Form()] = "",
) -> HTMLResponse | RedirectResponse:
    gate = await require_session(request)
    if gate is None:
        return RedirectResponse(f"/login?next=/events/{event_id}/edit", status_code=303)
    user, token = gate

    event, token = await call_with_reauth(request, token, lambda t: events_service.get_event(event_id, access_token=t))
    if event is None:
        set_flash(request, "That event no longer exists.", "error")
        return RedirectResponse("/", status_code=303)
    if not rbac.is_organizer(user.custom_role) or event.organizer_id != user.id:
        set_flash(request, "Only this event's organizer can edit it.", "error")
        return RedirectResponse(f"/events/{event_id}", status_code=303)

    try:
        values = EventFormValues(title=title, description=description, starts_at=starts_at, location=location, capacity=capacity)
    except ValidationError as exc:
        context = await build_base_context(request)
        context.update(
            {"errors": _field_errors(exc), "form_error": None, "event": event, "starts_at_value": starts_at}
        )
        return templates.TemplateResponse(request=request, name="event_form.html", context=context, status_code=422)

    actor_id, actor_name = _actor_fields(user)
    try:
        updated, token = await call_with_reauth(
            request, token, lambda t: events_service.update_event(event, values, access_token=t)
        )
        await call_with_reauth(
            request,
            token,
            lambda t: log_activity(event_id=updated.id, actor_id=actor_id, actor_name=actor_name, action="event_updated", access_token=t),
        )
    except MudbaseApiError as exc:
        context = await build_base_context(request)
        context.update(
            {"errors": {}, "form_error": exc.message, "event": event, "starts_at_value": starts_at}
        )
        return templates.TemplateResponse(request=request, name="event_form.html", context=context, status_code=400)

    set_flash(request, "Event updated.", "success")
    return RedirectResponse(f"/events/{event_id}", status_code=303)


@router.post("/events/{event_id}/delete", response_model=None)
async def delete_event_submit(request: Request, event_id: str) -> RedirectResponse:
    gate = await require_session(request)
    if gate is None:
        return RedirectResponse(f"/login?next=/events/{event_id}", status_code=303)
    user, token = gate

    event, token = await call_with_reauth(request, token, lambda t: events_service.get_event(event_id, access_token=t))
    if event is None:
        set_flash(request, "That event no longer exists.", "error")
        return RedirectResponse("/", status_code=303)
    if not rbac.is_organizer(user.custom_role) or event.organizer_id != user.id:
        set_flash(request, "Only this event's organizer can delete it.", "error")
        return RedirectResponse(f"/events/{event_id}", status_code=303)

    try:
        await call_with_reauth(request, token, lambda t: events_service.delete_event(event, access_token=t))
    except MudbaseApiError as exc:
        set_flash(request, f"Couldn't delete this event: {exc.message}", "error")
        return RedirectResponse(f"/events/{event_id}", status_code=303)

    set_flash(request, "Event deleted.", "success")
    return RedirectResponse("/", status_code=303)


def _field_errors(exc: ValidationError) -> dict[str, str]:
    errors: dict[str, str] = {}
    for error in exc.errors():
        field = str(error["loc"][0]) if error["loc"] else "form"
        errors[field] = error["msg"]
    return errors
