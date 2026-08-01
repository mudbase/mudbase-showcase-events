"""events collection: read granted to both roles, create/update/delete
restricted to organizer — enforced server-side by Mudbase collection
permissions (see plan/build-plan.md), re-checked here as defense-in-depth
by `app/rbac.py` plus an inline `organizer_id == user.id` ownership check in
`app/routers/events.py` (ownership is per-document, so it can't live in
rbac.py's role-only checks). Mirrors ../web/src/hooks/useEvents.ts.
"""

import asyncio

from app.config import get_settings
from app.mudbase_client import create_data_sync, delete_data_sync, get_data_sync, list_data_sync, update_data_sync
from app.schemas.event import EventDoc, EventFormValues
from app.schemas.pagination import PaginationMeta

_EVENTS_PAGE_SIZE = 10


async def list_events(*, page: int, access_token: str) -> tuple[list[EventDoc], PaginationMeta]:
    settings = get_settings()
    result = await asyncio.to_thread(
        list_data_sync,
        settings.events_collection_id,
        sort="startsAt",
        page=page,
        limit=_EVENTS_PAGE_SIZE,
        access_token=access_token,
    )
    events = [EventDoc.model_validate(doc) for doc in result["data"]]
    pagination = PaginationMeta.model_validate(result["pagination"] or {})
    return events, pagination


async def get_event(event_id: str, *, access_token: str) -> EventDoc | None:
    settings = get_settings()
    doc = await asyncio.to_thread(get_data_sync, settings.events_collection_id, event_id, access_token=access_token)
    return EventDoc.model_validate(doc) if doc else None


async def create_event(
    values: EventFormValues,
    *,
    organizer_id: str,
    organizer_name: str,
    access_token: str,
) -> EventDoc:
    settings = get_settings()
    body: dict[str, object] = {
        "title": values.title,
        "startsAt": values.starts_at_iso(),
        "location": values.location,
        "capacity": values.capacity,
        "organizerId": organizer_id,
        "organizerName": organizer_name,
    }
    if values.description:
        body["description"] = values.description
    doc = await asyncio.to_thread(create_data_sync, settings.events_collection_id, body, access_token=access_token)
    return EventDoc.model_validate(doc)


async def update_event(event: EventDoc, values: EventFormValues, *, access_token: str) -> EventDoc:
    settings = get_settings()
    body: dict[str, object] = {
        "title": values.title,
        "description": values.description or "",
        "startsAt": values.starts_at_iso(),
        "location": values.location,
        "capacity": values.capacity,
    }
    doc = await asyncio.to_thread(
        update_data_sync, settings.events_collection_id, event.id, body, access_token=access_token
    )
    return EventDoc.model_validate(doc)


async def delete_event(event: EventDoc, *, access_token: str) -> None:
    settings = get_settings()
    await asyncio.to_thread(delete_data_sync, settings.events_collection_id, event.id, access_token=access_token)
