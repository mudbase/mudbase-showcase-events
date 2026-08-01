"""Login / register / logout. Mirrors ../web/src/hooks/useAuth.ts. Unlike
the sibling kanban port (no self-registration at all) but like the sibling
social/ecommerce ports, this app does have a registration flow — the
difference here is a real `role` selector (organizer/attendee) instead of a
single hardcoded default role, since Mudbase's signup slug is part of the
URL path (`/api/auth/local/signup/{role}`)."""

import asyncio
from typing import Any

from app.mudbase_client import login_sync, logout_sync, register_with_role_sync


async def register(
    role: str,
    email: str,
    password: str,
    first_name: str,
    last_name: str,
    agreed_to_terms: bool,
) -> dict[str, Any]:
    return await asyncio.to_thread(register_with_role_sync, role, email, password, first_name, last_name, agreed_to_terms)


async def login(email: str, password: str) -> dict[str, Any]:
    return await asyncio.to_thread(login_sync, email, password)


async def logout(access_token: str) -> None:
    await asyncio.to_thread(logout_sync, access_token)
