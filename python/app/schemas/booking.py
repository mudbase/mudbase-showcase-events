"""Mirrors ../web/src/types/booking.ts. Field aliases match the raw Mudbase
document shape (camelCase, `_id`) so `BookingDoc.model_validate(doc)` works
directly off a `DataApi` response dict — no separate mapping layer.
"""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

BookingStatus = Literal["confirmed", "waitlisted", "cancelled", "checked_in"]


class BookingDoc(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str = Field(alias="_id")
    event_id: str = Field(alias="eventId")
    user_id: str = Field(alias="userId")
    user_name: str = Field(alias="userName")
    status: BookingStatus
    qr_token: str = Field(alias="qrToken")
    created_at: datetime | None = Field(default=None, alias="createdAt")
    updated_at: datetime | None = Field(default=None, alias="updatedAt")
