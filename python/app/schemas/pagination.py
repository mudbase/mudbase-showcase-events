"""Mirrors ../web/src/lib/mudbase.ts::PaginationMeta — the raw Mudbase
`DataApi.list_data` pagination envelope, parsed once here so every router
that paginates (currently just the event list) shares one shape."""

from pydantic import BaseModel, ConfigDict, Field


class PaginationMeta(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    page: int
    limit: int
    total: int
    total_pages: int = Field(alias="totalPages")
    has_more: bool = Field(alias="hasMore")
