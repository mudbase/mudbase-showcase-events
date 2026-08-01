"""Server-side mirror of ../web/src/hooks/useAuth.ts's role checks
(isOrganizer/isAttendee) and ../web/plan/build-plan.md's RBAC matrix.

Unlike a client-side SPA, this app's role checks *are* part of the security
boundary that stands between an end user and Mudbase — there is no browser
JS to "just hide a button" here, every write goes through one of these
gates (or an inline ownership check in the router that has the specific
document loaded) before this app's own request handler ever calls Mudbase.
That said, Mudbase's own collection permissions remain the ultimate
enforcement layer — these functions are this app's own defense-in-depth
check, not a replacement for it.

Ownership checks (`event.organizer_id == user.id`) are inherently
per-document rather than per-role, so they live inline in
`app/routers/events.py` / `app/routers/bookings.py` where the specific event
or booking is already loaded, not here.
"""

_KNOWN_ROLES = frozenset({"organizer", "attendee"})
_ROLE_LABELS = {"organizer": "Organizer", "attendee": "Attendee"}


def is_organizer(role: str | None) -> bool:
    return role == "organizer"


def is_attendee(role: str | None) -> bool:
    return role == "attendee"


def is_known_role(role: str | None) -> bool:
    return role in _KNOWN_ROLES


def role_label(role: str | None) -> str:
    return _ROLE_LABELS.get(role or "", "Unknown")
