# Build Plan — Mudbase Showcase: Events (Python)

Generated: 2026-08-01
Mode: port (Python, server-rendered)
Type: web (fullstack via BaaS, no custom backend)
Stack: FastAPI (async) + Jinja2 templates + vanilla CSS, backed entirely by the real Mudbase
Python SDK (`mudbase-sdk`, generated via OpenAPI Generator), against the same live Mudbase
project as `../web`.

## Stack Decisions

- FastAPI + Jinja2 + vanilla CSS, no bundler, no client-side JS beyond plain HTML forms: matches
  the sibling `mudbase-showcase-social/python` and `mudbase-showcase-kanban/python` ports exactly —
  same dependency set, same architecture (`app/config.py`, `app/mudbase_client.py`,
  `app/session.py`, `app/context.py`, `app/templates_env.py`, `app/routers/*`, `app/services/*`,
  `app/schemas/*`), per this task's explicit instruction to mirror that established framework
  choice rather than introduce a new one.
- **QR codes rendered server-side as real scannable PNGs**, not the reference SPA's client-side
  `<QRCodeSVG>`. `app/services/qrcode_service.py` uses the pure-Python `qrcode[pil]` library to
  render each booking's `qrToken` as a base64 PNG data URI embedded directly in `<img>` — no
  separate image route, no client JS, matching this port's "no bundler" architecture while still
  giving organizers a genuinely scannable code (not just a raw text string) on the bookings page.
- **No realtime.** The reference `../web` app doesn't use Socket.IO for this project — a page
  reload is already how a visitor sees another user's change in this app too, so there is no
  divergence here to document (unlike the kanban/social ports).
- **Registration ships with a real role toggle** (organizer/attendee), unlike the sibling kanban
  port (no self-registration at all) — this project's two roles are both self-registerable via
  Mudbase's per-role signup slug (`/api/auth/local/signup/{role}`), matching
  `../web/src/components/auth/RegisterForm.tsx`'s own role selector exactly.

## Real, Already-Provisioned Mudbase Project (used as-is, not recreated)

- Base URL `https://cloud.mudbase.dev`, project ID `6a6d3fa9d07caabbbdfc564f`.
- `events` — `6a6d3fcad07caabbbdfc5802` — `title`, `description?`, `startsAt`, `location`,
  `capacity`, `organizerId`, `organizerName`.
- `bookings` — `6a6d3fcbd07caabbbdfc5819` — `eventId`, `userId`, `userName`, `status`
  (`confirmed`/`waitlisted`/`cancelled`/`checked_in`), `qrToken`.
- `activity` — `6a6d3fccd07caabbbdfc582e` — `eventId`, `actorId`, `actorName`, `action`.
- Roles: `organizer` (full CRUD on all three collections), `attendee` (read events; create/read/
  update own bookings; create/read activity). Signup slugs are exactly `organizer` and `attendee`.
- Two pre-verified shared demo accounts (see README) — used directly for the live verification
  below; additional bookers needed to exercise the capacity/waitlist algorithm with multiple
  distinct users were exercised via direct service-layer calls using the organizer's own token
  (organizer has unrestricted CRUD on `bookings`) rather than by registering more throwaway
  accounts against the shared, rate-limited signup endpoint — see "Live Verification" below for why.

## Auth Model (no anonymous session — every role signs in)

Same constraint as `../web`: there is no anonymous/guest session and no public read in this app.
Both roles (`organizer`/`attendee`) require a real login — `app/session.py::require_session` is
this port's equivalent of the reference SPA's `<AuthGate>`; every page handler except `/login` and
`/register` calls it first and redirects to `/login?next=<path>` if there is no valid session.

**One deliberate exception, matching the reference app's own actual UI exactly**: `GET /` shows an
inline "Sign in to see upcoming events" prompt for an unauthenticated visitor rather than a
redirect — this is what `../web/src/app/page.tsx` itself renders (see its own `!loading &&
!isAuthenticated` branch), so this port matches that literal behavior instead of the generic
redirect-to-login pattern used everywhere else.

`app/mudbase_client.py::login_sync` bypasses the SDK's generated typed `login_local_user` method
in favor of a raw JSON call via the SDK's own public `param_serialize`/`call_api` primitives —
ported verbatim from the sibling ports' identical finding: the generated response's nested user
model doesn't declare a `customRole` field, even though the real Multi-Role feature returns one,
and this app needs `customRole` on every login to tell organizer/attendee apart.
`register_with_role_sync` uses the typed `MultiRoleFeatureApi.register_with_role` method directly
(no such workaround needed there — that response model is complete), same as the sibling
social/ecommerce ports' own registration flow.

## RBAC (enforced server-side by Mudbase's own collection permissions; this app's own checks are defense-in-depth, not the boundary)

| Action | organizer | attendee |
|---|---|---|
| Read events (list + detail) | yes | yes |
| Create / update / delete an event | yes (enforced server-side; `app/rbac.py::is_organizer` plus an inline `event.organizer_id == user.id` ownership check in `app/routers/events.py` before this app ever calls Mudbase) | no |
| Create a booking | app hides the Book button on an organizer's own event and blocks the POST route too (`event.organizer_id == user.id` check in `app/routers/bookings.py::book_event_submit`); not otherwise restricted by role | yes |
| Read/update own booking (cancel) | n/a (organizer bookings not modeled as a separate write path in this UI) | yes, own bookings only (`booking.user_id == session.user.id`, checked in `app/routers/bookings.py::cancel_booking_submit`) |
| Check others in via QR token | yes (own events only — `app/routers/bookings.py::checkin_page`/`checkin_submit`) | no — app redirects with a flash message, the check-in routes are never reachable |
| Read activity log | yes | yes |
| Write activity | yes (via event/booking actions) | yes (via booking actions on own bookings) |

Unlike a client-side SPA, this server-rendered app's own role/ownership checks genuinely are part
of its security posture (there is no browser JS to bypass here) — but the real, final enforcement
boundary is still Mudbase's own collection permissions. See "Live Verification" below for a raw
API confirmation of that independent enforcement, exactly as the sibling kanban port's build-plan
documents for its own three-role matrix.

## Data Models (Pydantic — mirror `../web/src/types/*.ts` field-for-field)

`app/schemas/event.py::EventDoc`, `app/schemas/booking.py::BookingDoc`,
`app/schemas/activity.py::ActivityEntry` — all use `populate_by_name=True` plus camelCase
`Field(alias=...)` so `Model.model_validate(doc)` works directly off a raw `DataApi` response dict,
no separate mapping layer. Every `...Id` field this app writes into a query filter (`organizerId`,
`eventId`, `userId`) is always a real Mudbase-issued 24-hex ObjectId — the signed-in user's session
`id`, or another document's real `_id` — never a client-invented string, per the platform's
query-sanitizer requirement.

**`EventFormValues.starts_at`** arrives as the raw `<input type="datetime-local">` string
(`YYYY-MM-DDTHH:MM`). The reference SPA converts it with `new Date(value).toISOString()`, which
implicitly uses the *visitor's own browser timezone* — a server-rendered app has no browser to ask,
so `EventFormValues.starts_at_iso()` treats the submitted wall-clock value as UTC directly. This is
a deliberate, documented simplification (see "Known Limitations"), not an oversight: getting the
visitor's real timezone into a plain HTML form with zero client JS isn't possible without either a
hidden JS-populated field (which this port intentionally doesn't have) or an explicit timezone
selector this task didn't ask for.

## Capacity-Race Handling Approach (ported field-for-field from `../web/src/lib/capacity.ts` and `../web/src/hooks/useBookings.ts`)

Mudbase is a generic-CRUD BaaS with no cross-document transactions or atomic counters, so a plain
"count, then decide, then create" is inherently racy. This app narrows (does not fully eliminate)
the race window with the exact same two-step approach as the reference app:

1. **Decide** (`app/services/bookings.py::create_booking`): read the live confirmed-booking count
   via `pagination.total` (a real server-side count), and create the new booking `"confirmed"` if
   `count < capacity`, otherwise `"waitlisted"`.
2. **Reconcile** (`app/services/capacity.py::reconcile_event_capacity`): immediately after, re-fetch
   every non-cancelled booking for the event (confirmed + waitlisted) sorted `createdAt` ascending.
   The first `capacity` of them (creation order) are entitled to a confirmed seat; anything else
   still marked `"confirmed"` is demoted (logs `booking_waitlisted`), and anything entitled but not
   yet `"confirmed"` is promoted (logs `booking_promoted`). This self-heals the exact race the task
   describes. The same reconciliation runs after a **cancellation**, promoting the earliest
   waitlisted booking into the freed seat.

**One deliberate deviation from the TypeScript original**, documented up front rather than
discovered by trial and error: `capacity.ts`'s `RECONCILE_FETCH_LIMIT` is `1000` (safe for a
browser calling the raw REST API directly). This Python port goes through the real Mudbase Python
SDK, whose `DataApi.list_data` caps `limit` at 100 server-side — a known platform constraint
stated up front in this task's brief, and the exact constraint the sibling
`mudbase-showcase-kanban/python` port's build-plan documents hitting *live* when it copied a
too-high limit in from its own reference app. This port's `_RECONCILE_FETCH_LIMIT = 100` was set
correctly from the start rather than rediscovered as a bug.

**Does not run after check-in**, per the task's literal spec: capacity is defined in terms of
`"confirmed"` bookings specifically, and check-in transitions `confirmed → checked_in` — running
reconciliation there would incorrectly free that person's physical seat for someone else on the
waitlist while they're still present. One real, live consequence of this exact rule (caught during
this build's own verification, not a bug): once a confirmed booking is checked in, the **live
confirmed count for new bookings drops by one** (checked-in bookings aren't counted as
`"confirmed"`), so a *new* booking can be freshly decided `"confirmed"` even though the event's
physical seats haven't changed. This is not a bug — it is the literal, inevitable consequence of a
capacity rule that only counts `"confirmed"` bookings, and it is identically present in the
reference `../web` app since it is the same ported algorithm; documented here so it isn't
mistaken for a discrepancy in this port specifically.

## Check-In Flow (`app/routers/bookings.py::checkin_page`/`checkin_submit`, `app/services/bookings.py::check_in_by_qr_token`)

Organizer-only, own events only. A single text input for a pasted/typed `qrToken`:
- No match → "No booking found for this code at this event." (no mutation)
- `"checked_in"` → "`{name}` was already checked in." (idempotent, no mutation)
- `"cancelled"` → "`{name}` was cancelled." (no mutation)
- `"waitlisted"` → "`{name}` is on the waitlist, not confirmed — cannot check in." (no mutation)
- `"confirmed"` → `PATCH → "checked_in"`, logs `checked_in`, shows a success message with the
  attendee's name.

Message copy is ported directly from `../web/src/components/bookings/CheckInForm.tsx::RESULT_COPY`,
including its per-outcome fallback name choices ("Guest" for a fresh check-in, "This guest" for
already-checked-in/waitlisted, "This booking" for cancelled) — kept for fidelity even though the
"This booking was cancelled" fallback reads a little oddly when a real name is substituted in
(`{name} was cancelled.`); this is a straight port of the reference copy, not a rewrite.

## Auth Flow

```
Visit any page except /, /login, /register with no session
                                  → require_session() returns None → redirect to
                                    /login?next=<original path>
Visit / with no session          → inline "Sign in to see upcoming events" prompt (see "Auth Model")
POST /login                       → app.mudbase_client.login_sync → 200 + token/refreshToken +
                                     user.customRole ("organizer"/"attendee")
POST /register                    → app.mudbase_client.register_with_role_sync(role, ...) →
                                     signed straight in if the project doesn't require email
                                     verification, else redirected to /login with a flash notice
401 on any authenticated call     → app.session.call_with_reauth refreshes once (single-use
                                     rotating refresh token) → retries the original call once →
                                     propagates the error if that also fails
POST /logout                      → best-effort remote revoke, then the local session cookie is
                                     always cleared regardless of the remote call's outcome
```

## Security Implementation

- Input validation: Pydantic models at every form boundary (`app/schemas/auth.py`,
  `app/schemas/event.py`) — 200-char title/location caps, 2000-char description cap, capacity
  1..100,000, matching `../web/src/components/events/EventForm.tsx`'s zod schema exactly.
- Authentication: Mudbase-issued JWT (access + refresh) held only in the signed, httpOnly
  Starlette session cookie (`SessionMiddleware`, `app/main.py`) — never sent to browser JS, unlike
  the reference SPA which necessarily holds its token in `localStorage` for direct
  browser-to-Mudbase calls.
- Authorization: enforced server-side by Mudbase's own collection permissions per the RBAC matrix
  above; `app/rbac.py` plus inline ownership checks are this app's own defense-in-depth, not the
  final boundary — see "Live Verification" for a raw API proof of the platform-level enforcement.
- Secrets: `SESSION_SECRET_KEY` is the only real secret in this app (signs the session cookie),
  loaded from the environment via `pydantic-settings`, never hardcoded, never logged. No Mudbase
  service-role credential exists anywhere in this app — every request authenticates with the
  signed-in user's own JWT.
- Rate limiting: inherited from Mudbase's own per-endpoint limits — directly encountered on this
  Mac's IP during this exact build (see "Live Verification").

## Known Limitations / Design Decisions

- **No timezone awareness on event start times** (see "Data Models" above) — the submitted
  `datetime-local` wall-clock value is treated as UTC directly, since a server-rendered app with no
  client JS has no way to learn the visitor's browser timezone the way the reference SPA's
  `new Date(...).toISOString()` implicitly does. A deliberate, documented simplification.
- **Capacity accounting counts `"confirmed"` only, not `"checked_in"`** (see "Capacity-Race
  Handling Approach") — the task's literal spec, identical to the reference `../web` app's own
  documented decision, including the same live consequence (checking someone in frees a "confirmed"
  slot for a new booking even though their physical seat is unchanged).
- **Reconciliation is a best-effort, non-transactional self-heal**, not a hard guarantee — inherent
  to building on a generic-CRUD BaaS with no cross-document transactions, same tradeoff the
  reference app and sibling showcases document for their own check-then-act uniqueness guards.
- **QR codes are rendered server-side as PNGs**, not the reference SPA's client-side SVG component
  — a deliberate architecture choice (see "Stack Decisions"), not a feature gap: the rendered code
  is genuinely scannable, just produced by a different (equally valid) mechanism.
- **Event deletion does not cascade its bookings/activity rows** — matches
  `../web/src/hooks/useEvents.ts::useDeleteEvent`, which only deletes the event document itself.

## Live Verification (2026-08-01, against the real project)

**Local Mac IP was already rate-limited on the auth endpoint** before any login attempt from this
build — a raw `curl` directly against `cloud.mudbase.dev`'s `/api/auth/local/login` returned
`429 {"error":"Too many requests from this IP, please try again later."}`, confirmed independent of
this app's own code, consistent with this exact finding already documented by the sibling
`mudbase-showcase-social/python` and `mudbase-showcase-kanban/python` ports' build-plans (shared
egress IP, concurrently-worked sibling projects). Per this task's explicit instruction not to block
a turn waiting on a rate-limit window, the full authenticated round-trip was run instead from the
`mudhaxk-vps` VPS (a different egress IP, not rate-limited): this exact `app/` tree was rsynced
over, dependencies installed fresh, and the real app run for real via `uvicorn` on
`http://127.0.0.1:8020`, exercised with `curl` end-to-end — not a simulation.

**Structural verification** (before any authenticated call):

| Check | Result |
|---|---|
| `mypy app` (strict, per `mypy.ini`) | ✅ "Success: no issues found in 26 source files" (both locally and on the VPS, fresh venv) |
| `GET /` with no session | ✅ `200`, renders the inline "Sign in to see upcoming events" prompt |
| `GET /bookings` with no session | ✅ `303` → `/login?next=/bookings` |
| `GET /events/<id>` with no session | ✅ `303` → `/login?next=/events/<id>` |
| `GET /login` | ✅ `200`, renders both "Sign in as Organizer/Attendee" quick-fill forms |
| `GET /register` | ✅ `200`, renders the organizer/attendee role toggle |
| `GET /static/css/styles.css` | ✅ `200` |
| `GET /does-not-exist` | ✅ `404` |
| `POST /login` with a malformed email (`not-an-email`) | ✅ `422`, Pydantic's `EmailStr` rejects it locally, before any Mudbase call is made |

**Authenticated round-trip, through the real running app (not raw API calls) unless noted**:

| Step | Result |
|---|---|
| Organizer login (`events.organizer.demo@gmail.com`) | ✅ `303`, `customRole: "organizer"` |
| Attendee login (`events.attendee.demo@gmail.com`) | ✅ `303`, `customRole: "attendee"` |
| Organizer creates Event A (capacity 2) via `POST /events` | ✅ `303` → `/events/<id>` |
| Organizer creates Event B (capacity 2, for the race-simulation test) | ✅ `303` |
| Real attendee books Event A (`POST /events/<id>/book`, 0 confirmed so far) | ✅ decided `"confirmed"`, flash "You're confirmed!", `booking_confirmed` logged |
| Second booker fills Event A to capacity (via `bookings_service.create_booking` directly, using the organizer's own token — see note below) | ✅ decided `"confirmed"` (2/2), `booking_confirmed` logged |
| Third booker on Event A (capacity full) | ✅ decided `"waitlisted"`, `booking_waitlisted` logged — capacity enforcement confirmed correct |
| **Race simulation** — 3 bookings force-written `"confirmed"` directly on Event B (capacity 2), simulating 3 concurrent requests that all read the same pre-write count | ✅ all 3 written `"confirmed"` — the race |
| `reconcile_event_capacity` run directly against Event B | ✅ exactly 1 correction: the **latest**-created booking demoted `confirmed → waitlisted`; the earliest two stayed `"confirmed"` — self-healing confirmed correct, byte-for-byte the same outcome the reference `../web` app's own race simulation documents |
| Real attendee cancels their own confirmed Event A booking (`POST /bookings/<id>/cancel`) | ✅ `303`, `booking_cancelled` logged |
| Reconciliation after that cancellation | ✅ the earliest waitlisted booking (the third booker) promoted `waitlisted → confirmed`, `booking_promoted` logged — cancellation-triggered promotion confirmed correct |
| **Check-in** — organizer checks in the promoted booking by its `qrToken` (`POST /events/<id>/checkin`) | ✅ `status: "confirmed" → "checked_in"`, `checked_in` logged, success message with the attendee's name |
| Re-check-in the same `qrToken` | ✅ idempotent "already checked in" message, no mutation |
| Check-in the cancelled booking's `qrToken` | ✅ "was cancelled" message, no mutation |
| Check-in an unknown `qrToken` | ✅ "No booking found" message, no mutation |
| Check-in a genuinely waitlisted booking's `qrToken` | ✅ "on the waitlist, not confirmed" message, no mutation |
| Final `activity` feed on Event A's detail page, reverse-chronological | ✅ all 9 entries present, correctly ordered: `booking_waitlisted` → `booking_confirmed` → `checked_in` → `booking_promoted` → `booking_cancelled` → `booking_waitlisted` → `booking_confirmed` → `booking_confirmed` → `event_created` |
| **Attendee attempts `POST /events` (create) through the app** | ✅ **`303` redirect with flash `"Only organizers can create events."`, no event created** — this app's own `app/rbac.py` gate, not yet the platform |
| Attendee `GET /events/<id>/edit`, `/checkin`, `POST /events/<id>/delete` (app-level) | ✅ all `303` redirects, no mutation reached Mudbase |
| **Attendee raw `POST` to the `events` collection with their own real JWT (bypassing this app)** | ✅ **`403 {"error":"Insufficient permissions","required":{"action":"create","collection":"events"},"customRole":"attendee"}`** |
| **Attendee raw `PATCH` on a real event `_id`** | ✅ **`403`, same shape, `action:"update"`** |
| **Attendee raw `DELETE` on a real event `_id`** | ✅ **`403`, same shape, `action:"delete"`** |
| Event A confirmed unchanged after all three raw attendee attempts | ✅ still present, capacity unchanged |
| Cleanup: organizer deletes Events A/B and every synthetic booking/activity row created for this verification | ✅ all removed; shared project confirmed back to its pre-test state |

**On using the organizer's own token for extra bookers instead of registering more throwaway
accounts**: this project's registration flow returned a "check your inbox for a verification link"
response rather than an immediate session for a freshly-registered throwaway account (email
verification is required on this project, same finding the sibling social/ecommerce ports
document), which makes registering disposable test accounts impractical without a real inbox to
check. Since the RBAC matrix grants `organizer` unrestricted CRUD on `bookings` (not scoped to
`userId === self`, unlike `attendee`), the organizer's own real, live JWT was used to drive
`app/services/bookings.py::create_booking` directly for the second/third/fourth/fifth bookers in
the capacity test above — this exercises the exact same production code path (decide from a live
count, write, log activity, reconcile, re-read) a genuine additional attendee's booking would, just
without a second real email inbox in the loop. The single real attendee account's own booking,
cancellation, and every check-in/RBAC assertion above went through the actual HTTP routes with a
real per-user session, not a bypass.

**Net result**: the entire app-to-Mudbase contract this app relies on — multi-role auth, event CRUD
with correctly-enforced RBAC, capacity-checked booking (confirmed vs. waitlisted), race-condition
self-healing via reconciliation, cancellation-triggered waitlist promotion, all five QR-token
check-in outcomes, and activity logging — is proven correct against the real, live backend, through
the real running FastAPI app (plus direct exercise of the same service functions for the
multi-booker capacity scenarios). The task's core security claim is independently verified:
**attendee's organizer-only-write restrictions are enforced by Mudbase's own collection permissions
server-side (`403 Insufficient permissions`), not merely by this app's own `app/rbac.py` checks or
its UI hiding the buttons** — confirmed with three different raw write attempts (create/update/
delete on `events`) using a real JWT that never passed through this app's own request handlers.

## Environment Variables

See `.env.example` — every Mudbase ID defaults to this showcase's real, already-provisioned
project. `SESSION_SECRET_KEY` is the only value that must be freshly generated per deployment.

## File Tree

```
mudbase-showcase-events/python/
├── requirements.txt, mypy.ini, .env.example, .gitignore, README.md
├── plan/build-plan.md
└── app/
    ├── __init__.py, config.py, context.py, main.py, mudbase_client.py, rbac.py, session.py,
    │   templates_env.py, utils.py
    ├── routers/ (auth.py, events.py, bookings.py)
    ├── schemas/ (auth.py, event.py, booking.py, activity.py, pagination.py)
    ├── services/ (auth_service.py, events.py, bookings.py, capacity.py, activity.py, qrcode_service.py)
    ├── static/css/styles.css
    └── templates/
        ├── base.html, login.html, register.html, index.html, event_form.html,
        │   event_detail.html, checkin.html, bookings.html
        └── partials/ (event_card.html, activity_item.html, booking_card.html)
```
