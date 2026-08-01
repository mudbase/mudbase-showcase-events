"""Mirrors ../web/src/types/activity.ts. `action` is a free string rather
than a Python enum on purpose (same choice the sibling kanban port makes) —
rendering falls back to the raw string for anything unrecognized, so a
future extra action type never breaks the feed. `ACTIVITY_LABELS` mirrors
../web/src/types/activity.ts::ACTIVITY_LABELS exactly.
"""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class ActivityEntry(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str = Field(alias="_id")
    event_id: str = Field(alias="eventId")
    actor_id: str = Field(alias="actorId")
    actor_name: str = Field(alias="actorName")
    action: str
    created_at: datetime | None = Field(default=None, alias="createdAt")


ACTIVITY_LABELS: dict[str, str] = {
    "booking_confirmed": "booked (confirmed)",
    "booking_waitlisted": "joined the waitlist",
    "booking_cancelled": "cancelled their booking",
    "booking_promoted": "was promoted from the waitlist",
    "checked_in": "checked in",
    "event_created": "created this event",
    "event_updated": "updated this event",
}
