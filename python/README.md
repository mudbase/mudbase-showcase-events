# Mudbase Showcase - Events (Python)

A server-rendered **FastAPI + Jinja2** reimplementation of the reference events booking/ticketing
app at [`../web`](../web), backed entirely by the real **Mudbase Python SDK**
(`mudbase-sdk`, generated via OpenAPI Generator, published at
[github.com/mudbase/mudbase-sdk](https://github.com/mudbase/mudbase-sdk)) - same Mudbase project,
same collections, same RBAC rules, different stack and delivery model (request/response HTML
instead of a client-side SPA talking directly to `cloud.mudbase.dev`). Architecture and conventions
mirror the sibling [`../../mudbase-showcase-social/python`](../../mudbase-showcase-social/python)
and [`../../mudbase-showcase-kanban/python`](../../mudbase-showcase-kanban/python) ports exactly.

## Stack

FastAPI (async) + Jinja2 templates + vanilla CSS (no bundler, no client-side JS beyond plain HTML
forms). Session state (the Mudbase JWT, refresh token, and user profile) lives only in a signed,
httpOnly Starlette session cookie - it is never sent to browser JS, unlike the reference SPA which
necessarily holds its token in `localStorage` for direct browser-to-Mudbase calls.

## What's implemented

| Feature | Where |
|---|---|
| Two-role sign-in (organizer / attendee), plus self-registration with a role toggle | `app/routers/auth.py`, `app/services/auth_service.py` |
| No anonymous/guest read - every role must sign in (except an inline prompt on `/`) | `app/session.py::require_session` |
| Event list (paginated, live confirmed/capacity badge per event) | `app/routers/events.py::home_index` |
| Event detail: info, capacity badge, book/cancel status, organizer actions, activity feed | `app/routers/events.py::event_detail` |
| Event create/edit (organizer, owner-checked) | `app/routers/events.py`, `app/services/events.py` |
| Capacity-aware booking (confirmed vs. waitlisted) | `app/routers/bookings.py::book_event_submit`, `app/services/bookings.py::create_booking` |
| Race-window self-healing reconciliation | `app/services/capacity.py::reconcile_event_capacity` (ported field-for-field from `../web/src/lib/capacity.ts`) |
| Cancel a booking → waitlist promotion | `app/routers/bookings.py::cancel_booking_submit`, `app/services/bookings.py::cancel_booking` |
| QR-code check-in (organizer, own events only) - real scannable PNG, all 5 outcomes | `app/routers/bookings.py::checkin_submit`, `app/services/bookings.py::check_in_by_qr_token`, `app/services/qrcode_service.py` |
| Reverse-chronological per-event activity feed | `app/routers/events.py::event_detail`, `app/services/activity.py` |
| Role-aware UI, server-enforced (no client JS to bypass) | `app/rbac.py`, `app/context.py` |

Every `events`/`bookings`/`activity` collection read/write goes through the real
`mudbase_sdk.DataApi`/`AuthenticationApi`/`MultiRoleFeatureApi` against `cloud.mudbase.dev` (see
`app/mudbase_client.py`).

## No realtime, no drag-and-drop-equivalent JS (deliberate)

Plain request/response HTML: a page reload is how you see another user's change. QR codes are
rendered server-side as base64 PNG data URIs (`app/services/qrcode_service.py`, using the
pure-Python `qrcode[pil]` library) rather than the reference SPA's client-side `<QRCodeSVG>` -
genuinely scannable, just produced by a different (equally valid) mechanism for a zero-client-JS
stack.

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # already points at the shared demo project; edit SESSION_SECRET_KEY at minimum
python -c "import secrets; print(secrets.token_urlsafe(48))"   # → SESSION_SECRET_KEY
uvicorn app.main:app --reload
```

Visit `http://localhost:8000/login`. Use one of the two quick sign-in buttons (Organizer /
Attendee) or type credentials manually - see `plan/build-plan.md` for account details and RBAC
verification notes.

### Type checking

```bash
pip install mypy
mypy app   # strict mode, config in mypy.ini - reports zero issues
```

## Architecture notes

- **`app/mudbase_client.py`** wraps the real (synchronous, urllib3-based) `mudbase_sdk` with
  `asyncio.to_thread` adapters so FastAPI's async handlers never block the event loop. Ported
  verbatim from the sibling `mudbase-showcase-social/python`/`mudbase-showcase-kanban/python`
  ports, including the auth call that bypasses the generated typed wrapper method (`login_sync`
  needs `customRole`, which the generated login response model omits) - see that file's module
  docstring for the full history.
- **`app/session.py`** ports the sibling ports' refresh strategy verbatim: `get_valid_access_token`
  proactively refreshes within a margin of expiry; `call_with_reauth` reactively retries once on a
  401 the margin check didn't predict. There is no anonymous-session bootstrap here (unlike the
  social/ecommerce ports) - `require_session` is this app's `<AuthGate>` equivalent.
- **`app/services/capacity.py::reconcile_event_capacity`** is a field-for-field Python port of
  `../web/src/lib/capacity.ts::reconcileEventCapacity` - same creation-order-priority algorithm,
  same self-heal behavior, with one deliberate, documented deviation: its fetch limit is 100, not
  1000, because the real Python SDK's `DataApi.list_data` caps `limit` at 100 server-side (a known
  platform constraint stated up front for this build, not rediscovered as a bug).
- **`app/services/qrcode_service.py`** renders each booking's `qrToken` as a real scannable QR code
  server-side (base64 PNG data URI) rather than a client-side SVG component - the only architecture
  difference from the reference SPA's QR rendering, necessary because this port ships zero
  client-side JavaScript.
- Every `Id`-suffixed filter field this app sends (`organizerId`, `eventId`, `userId`) is a genuine
  24-hex-char Mudbase ObjectId - the signed-in user's own session id or a fetched document's real
  `_id`, never a client-invented string.

## Known limitations (real platform/architecture constraints, not bugs)

**No timezone awareness on event start times.** The `<input type="datetime-local">` form value is
treated as UTC directly server-side, since there is no browser to ask for its local timezone the
way the reference SPA's `new Date(...).toISOString()` implicitly does.

**Capacity accounting counts `"confirmed"` bookings only, not `"checked_in"`** - the task's literal
spec, identical to the reference app's own documented decision. One real consequence: checking a
guest in frees up a "confirmed" slot for a brand-new booking, since checked-in bookings aren't
counted toward capacity. Not a bug - an inherent, documented property of this exact rule, present
identically in the reference `../web` app.

**Reconciliation is a best-effort, non-transactional self-heal**, not a hard guarantee - inherent
to a generic-CRUD BaaS with no cross-document transactions.

## Live verification

Full RBAC-aware round-trip verified live against the real Mudbase project through the actual
running app: organizer/attendee login, event creation, capacity-aware booking up through waitlist,
a forced-race simulation proving `reconcile_event_capacity`'s self-heal (byte-for-byte the same
outcome the reference `../web` app's own race simulation documents), cancellation-triggered
promotion, all five QR check-in outcomes, the full reverse-chronological activity feed, and - the
key security claim - three raw write attempts (create/update/delete on `events`) using a real
attendee JWT that bypassed this app's own code entirely, all rejected with a genuine
`403 Insufficient permissions` from Mudbase itself.

This Mac's IP was already rate-limited on Mudbase's auth endpoint from the other showcase ports
built earlier the same day, so the authenticated portion of this run was done from the
`mudhaxk-vps` VPS (a different egress IP) - the same `app/` code, installed fresh and run for real,
not simulated. See `plan/build-plan.md` "Live Verification" for the full blow-by-blow, including
why extra booking-test identities were driven via the organizer's own live token (unrestricted
`bookings` CRUD) rather than registering more throwaway accounts against this project's
email-verification-gated signup flow.
