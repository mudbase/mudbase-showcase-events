"""activity collection: read granted to both roles; creation happens as a
side effect of event/booking writes (there is no direct end-user-facing
"post an activity row" action) — enforced server-side by Mudbase collection
permissions.

`action` values written by this app: `event_created`, `event_updated`,
`booking_confirmed`, `booking_waitlisted`, `booking_cancelled`,
`booking_promoted`, `checked_in` — the exact same set
../web/src/types/activity.ts::ActivityAction documents.
"""

import asyncio

from app.config import get_settings
from app.mudbase_client import create_data_sync, list_data_sync
from app.schemas.activity import ActivityEntry

# Per-event feed, mirrors ../web/src/hooks/useActivity.ts::useEventActivity's own limit of 50 —
# well under the real Python SDK's client-side `limit<=100` constraint on `DataApi.list_data`
# (a known platform fact this build already knows about; see mudbase-showcase-kanban/python's
# plan/build-plan.md for the live bug that constant caused there when copied in at 200 instead).
_FEED_LIMIT = 50


async def list_event_activity(event_id: str, *, access_token: str) -> list[ActivityEntry]:
    settings = get_settings()
    result = await asyncio.to_thread(
        list_data_sync,
        settings.activity_collection_id,
        filter_dict={"eventId": event_id},
        sort="-createdAt",
        limit=_FEED_LIMIT,
        access_token=access_token,
    )
    return [ActivityEntry.model_validate(doc) for doc in result["data"]]


async def log_activity(
    *,
    event_id: str,
    actor_id: str,
    actor_name: str,
    action: str,
    access_token: str,
) -> ActivityEntry:
    settings = get_settings()
    doc = await asyncio.to_thread(
        create_data_sync,
        settings.activity_collection_id,
        {"eventId": event_id, "actorId": actor_id, "actorName": actor_name, "action": action},
        access_token=access_token,
    )
    return ActivityEntry.model_validate(doc)
