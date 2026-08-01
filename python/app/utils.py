"""Small formatting helpers. Ported from the sibling mudbase-showcase-kanban/
mudbase-showcase-social Python ports' app/utils.py, plus two additions this
app specifically needs: `generate_qr_token` (a Python port of
../web/src/lib/utils.ts::generateQrToken) and `capacity_badge` (a Python
port of ../web/src/components/events/CapacityBadge.tsx's variant/label
logic, computed server-side here since there is no client component to
render it)."""

import math
import secrets
from datetime import datetime


def format_date(value: datetime | str | None) -> str:
    """Formats an ISO timestamp (or already-parsed datetime) for display."""
    if value is None:
        return ""
    parsed: datetime
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return value
    else:
        parsed = value
    return parsed.strftime("%b %-d, %Y, %-I:%M %p")


def initial(name: str | None) -> str:
    """First letter of a display name, uppercased, for the avatar circle.
    Falls back to "?" for an empty/missing name."""
    stripped = (name or "").strip()
    return stripped[0].upper() if stripped else "?"


def relative_time(value: datetime | str | None) -> str:
    """A short "2h ago"-style label for the activity feed, falling back to
    `format_date` for anything older than a week (where a relative label
    stops being useful)."""
    if value is None:
        return ""
    parsed: datetime
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return value
    else:
        parsed = value

    now = datetime.now(parsed.tzinfo) if parsed.tzinfo else datetime.now()
    delta_seconds = (now - parsed).total_seconds()
    if delta_seconds < 60:
        return "just now"
    if delta_seconds < 3600:
        minutes = int(delta_seconds // 60)
        return f"{minutes}m ago"
    if delta_seconds < 86400:
        hours = int(delta_seconds // 3600)
        return f"{hours}h ago"
    if delta_seconds < 604800:
        days = int(delta_seconds // 86400)
        return f"{days}d ago"
    return format_date(parsed)


def generate_qr_token() -> str:
    """A random, unguessable single-use check-in code — 32 hex characters
    (128 bits of entropy), the same shape as the reference web app's
    `crypto.randomUUID().replace(/-/g, "")`. Not a security credential in the
    cryptographic sense (this is a demo ticketing app, not a payments
    system); `secrets.token_hex` is used (not `random`) simply because it is
    the standard-library right tool for an unguessable token regardless."""
    return secrets.token_hex(16)


def capacity_badge(confirmed: int, capacity: int) -> tuple[str, str]:
    """Mirrors ../web/src/components/events/CapacityBadge.tsx's threshold
    logic exactly: full once confirmed >= capacity, "low" once the
    remaining seats drop to <= max(1, 10% of capacity), otherwise open.
    Returns (css_class, label)."""
    remaining = capacity - confirmed
    if remaining <= 0:
        return "badge-danger", f"Full · {confirmed}/{capacity}"
    threshold = max(1, math.ceil(capacity * 0.1))
    css_class = "badge-warning" if remaining <= threshold else "badge-success"
    return css_class, f"{confirmed}/{capacity} booked"
