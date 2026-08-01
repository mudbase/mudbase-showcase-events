"""Mirrors ../web/src/types/event.ts. Field aliases match the raw Mudbase
document shape (camelCase, `_id`) so `EventDoc.model_validate(doc)` works
directly off a `DataApi` response dict — no separate mapping layer.
"""

from datetime import datetime, timezone

from pydantic import BaseModel, ConfigDict, Field, field_validator

_MAX_TITLE_LENGTH = 200
_MAX_DESCRIPTION_LENGTH = 2000
_MAX_LOCATION_LENGTH = 200
_MIN_CAPACITY = 1
_MAX_CAPACITY = 100_000

# The <input type="datetime-local"> shape this app's forms submit: "YYYY-MM-DDTHH:MM".
_DATETIME_LOCAL_FORMAT = "%Y-%m-%dT%H:%M"


class EventDoc(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str = Field(alias="_id")
    title: str
    description: str | None = None
    starts_at: datetime = Field(alias="startsAt")
    location: str
    capacity: int
    organizer_id: str = Field(alias="organizerId")
    organizer_name: str = Field(alias="organizerName")
    created_at: datetime | None = Field(default=None, alias="createdAt")
    updated_at: datetime | None = Field(default=None, alias="updatedAt")


class EventFormValues(BaseModel):
    """Validated shape of the create/edit event form. Mirrors the zod schema
    in ../web/src/components/events/EventForm.tsx exactly (200-char title
    cap, 2000-char description cap, 200-char location cap, capacity 1..100000).

    `starts_at` arrives as the raw `datetime-local` form string. Unlike the
    reference SPA (which does `new Date(value).toISOString()` in the
    visitor's own browser timezone), this server-rendered app has no browser
    to ask — the submitted wall-clock value is treated as UTC directly (see
    plan/build-plan.md "Known Limitations" for why this is a deliberate,
    documented simplification rather than an oversight).
    """

    title: str = Field(min_length=1, max_length=_MAX_TITLE_LENGTH)
    description: str = Field(default="", max_length=_MAX_DESCRIPTION_LENGTH)
    starts_at: str
    location: str = Field(min_length=1, max_length=_MAX_LOCATION_LENGTH)
    capacity: int = Field(ge=_MIN_CAPACITY, le=_MAX_CAPACITY)

    @field_validator("title", "location")
    @classmethod
    def _strip_required(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("This field is required.")
        return stripped

    @field_validator("description")
    @classmethod
    def _strip_optional(cls, value: str) -> str:
        return value.strip()

    @field_validator("starts_at")
    @classmethod
    def _validate_starts_at(cls, value: str) -> str:
        try:
            datetime.strptime(value, _DATETIME_LOCAL_FORMAT)
        except ValueError as exc:
            raise ValueError("Enter a valid date and time.") from exc
        return value

    def starts_at_iso(self) -> str:
        """Converts the validated `datetime-local` string to an ISO 8601
        UTC instant for storage — see the class docstring for the timezone
        caveat."""
        parsed = datetime.strptime(self.starts_at, _DATETIME_LOCAL_FORMAT).replace(tzinfo=timezone.utc)
        return parsed.isoformat().replace("+00:00", "Z")


def starts_at_local_value(value: datetime) -> str:
    """The inverse of `EventFormValues.starts_at_iso` — formats a stored
    UTC instant back into the `datetime-local` input's expected value, for
    pre-filling the edit-event form. Mirrors
    ../web/src/lib/utils.ts::toDateTimeLocalValue."""
    if value.tzinfo is not None:
        value = value.astimezone(timezone.utc).replace(tzinfo=None)
    return value.strftime(_DATETIME_LOCAL_FORMAT)
