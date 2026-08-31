# Build Plan - Mudbase Showcase: Events (Go port)

Generated: 2026-08-01
Mode: port (Go server-rendered reimplementation of the already-built, live-tested Next.js
reference at `../web`, which remains the source of truth for the data model, RBAC matrix, and the
capacity/waitlist-promotion algorithm).
Type: web (server-rendered, fullstack via BaaS, no custom backend)
Stack: Go 1.26 + `net/http` + `chi/v5` + `html/template` + `gorilla/sessions`, backed entirely by
Mudbase (cloud.mudbase.dev) - mirrors `mudbase-showcase-social/go` and `mudbase-showcase-kanban/go`
architecture: `internal/mbase`, `internal/models`, `internal/store`, `internal/rbac`,
`internal/server`.

## Stack Decisions

- `net/http` + `chi/v5` + `html/template` + `gorilla/sessions`: matches the sibling Go showcase
  ports exactly, per this task's explicit instruction to mirror their architecture.
- `internal/mbase` ports the kanban/social showcases' client verbatim - 401 → refresh → retry
  wired through request context (`WithTokenRefresher`) and into every
  `mbase.List/Get/Create/Update/Delete` call, so no handler can forget it. The only functional
  addition versus kanban's `mbase` package: a `Register` method (`MultiRoleFeatureAPI.RegisterWithRole`)
  for the reference web app's nice-to-have `/register` page, since this project (like the web
  reference) has two real signup slugs (`organizer`/`attendee`) rather than kanban's operator-only
  provisioning.
- No custom backend of any kind: every persistence and auth concern is a Mudbase REST call made
  through the official Go SDK. The Mudbase JWT lives only in an encrypted, httpOnly session cookie
  (`internal/session`) - there is no client-side JavaScript in this port at all, so there is no
  other place a token could live.
- QR codes: `github.com/skip2/go-qrcode`, rendered server-side to a PNG and inlined as a base64
  `data:` URI (`internal/server/format.go`'s `qrDataURI`) - the server-rendered equivalent of the
  reference web app's `<QRCodeSVG>` (`qrcode.react`). Needs no client-side library and no extra
  round-trip.
- Zero client-side JavaScript: unlike the sibling kanban port (which polls two small `<script>`
  blocks to emulate a realtime board), this app ships none at all. Every mutation is a plain HTML
  form POST followed by a redirect (PRG) to the page that reflects the new state.

## Real, Already-Provisioned Mudbase Project (used as-is, not recreated)

- Base URL `https://cloud.mudbase.dev`, project ID `6a6d3fa9d07caabbbdfc564f`.
- `events` - `6a6d3fcad07caabbbdfc5802` - `title`, `description?`, `startsAt`, `location`,
  `capacity`, `organizerId`, `organizerName`.
- `bookings` - `6a6d3fcbd07caabbbdfc5819` - `eventId`, `userId`, `userName`, `status`
  (`confirmed`/`waitlisted`/`cancelled`/`checked_in`), `qrToken`.
- `activity` - `6a6d3fccd07caabbbdfc582e` - `eventId`, `actorId`, `actorName`, `action`.
- Roles: `organizer` (full CRUD on all three collections), `attendee` (read events; create/read/
  update own bookings; create/read activity). Signup slugs are exactly `organizer` and `attendee`.
- Two pre-verified shared test accounts: `events.organizer.demo@gmail.com` /
  `events.attendee.demo@gmail.com`, password `DemoTest123!` - used directly, no new registrations
  against the shared, rate-limited signup endpoint.

## Data Models (Go)

```go
// internal/models/event.go
type Event struct {
    ID, CreatedAt, UpdatedAt string
    Title, Description       string
    StartsAt, Location       string
    Capacity                 int
    OrganizerID, OrganizerName string
}

// internal/models/booking.go
type BookingStatus string // "confirmed" | "waitlisted" | "cancelled" | "checked_in"
type Booking struct {
    ID, CreatedAt, UpdatedAt string
    EventID, UserID, UserName string
    Status                    BookingStatus
    QRToken                   string
}

// internal/models/activity.go
type ActivityAction string // booking_confirmed | booking_waitlisted | booking_cancelled |
                            // booking_promoted | checked_in | event_created | event_updated
type Activity struct {
    ID, CreatedAt string
    EventID, ActorID, ActorName string
    Action ActivityAction
}
```

Every `...Id`/`...ID` field is always populated from a real Mudbase-issued 24-hex ObjectId (the
signed-in user's session ID, or another document's real `_id`) - never a client-invented string -
per the platform's query-sanitizer requirement (confirmed by the sibling ports; see "Known
platform facts" in the task brief).

## RBAC Matrix

See README.md "RBAC matrix" - identical content, reproduced there to keep the top-level doc
self-contained for a reader who doesn't open this file.

Server-side enforcement is the actual security boundary (Mudbase collection permissions,
role-level not per-document - any organizer account may CRUD any event); this app's own
`internal/rbac` package and `organizerId === session.user.id` template checks are UX gating so the
right people see the right buttons, matching the pattern established in every sibling showcase
port and in the reference web app itself (see `../web/plan/build-plan.md` "RBAC Matrix").

## Auth Flow

```
Login    → POST /api/auth/local/login {email,password,projectId} → {token, refreshToken, user}
           user.customRole is "organizer" or "attendee" - drives every role-gated UI branch.
           internal/mbase/auth.go re-decodes the raw response body because the vendored SDK's
           generated LoginLocalUser/GetCurrentSession/RefreshToken models omit customRole (a known
           SDK gap already documented by the social/kanban ports).
Session  → the Mudbase JWT + a cached user snapshot live in an encrypted, httpOnly session cookie
           (internal/session), never in client-side JS - there is none.
Refresh  → POST /api/auth/refresh {refreshToken} → new {token, refreshToken}; every
           mbase.List/Get/Create/Update/Delete call is retried exactly once on a 401 via a
           TokenRefresher threaded through request context (internal/mbase/refresh.go), which
           re-persists the rotated pair back into the session cookie.
Logout   → POST /api/auth/logout, then the local session cookie is cleared.
Register → POST (via MultiRoleFeatureAPI.RegisterWithRole) /api/auth/register/:role
           (role = "organizer" | "attendee", agreedToTerms: true required) - a nice-to-have signup
           path; the two shared demo accounts are the primary path used for the live smoke test.
```

No anonymous/guest session is attempted: this project's RBAC is scoped to `organizer`/`attendee`
only with no public role configured, so an unauthenticated visitor is redirected to `/login`
(`requireSignedIn` middleware) instead of a silently-bootstrapped anonymous session that would just
403 on every collection read anyway.

## Capacity-Race Handling Approach

See README.md "Capacity-race handling" for the full narrative - ported algorithmically from the
reference web app's `src/lib/capacity.ts` (`reconcileEventCapacity`) and `src/hooks/useBookings.ts`
(`useCreateBooking`/`useCancelBooking`), with the exact same two-phase decide-then-reconcile
approach:

1. `internal/store/bookings.go`'s `Create` counts confirmed bookings via a real server-side
   pagination total (`ConfirmedCount`), decides `confirmed` vs `waitlisted`, writes the booking,
   logs the corresponding activity row, then calls `ReconcileEventCapacity`.
2. `internal/store/capacity.go`'s `ReconcileEventCapacity` re-fetches every confirmed + waitlisted
   booking for the event, sorted `createdAt` ascending, and corrects any booking whose current
   status disagrees with "first `capacity` bookings, oldest first, hold a confirmed seat" -
   demoting an overshoot back to waitlisted, or promoting the earliest waitlisted booking once a
   seat frees up. Each correction logs `booking_promoted` or `booking_waitlisted`.
3. `Create` re-fetches its own just-created booking by ID after reconciliation, so the returned
   (and displayed) status is always the post-reconciliation truth, not the tentative initial write.
4. `Cancel` marks the booking `cancelled`, logs `booking_cancelled`, then runs the same
   reconciliation pass so a freed confirmed seat promotes the earliest waitlisted booking.
5. Deliberately **not** run after check-in - capacity is defined in terms of `"confirmed"` bookings
   specifically; running reconciliation there would incorrectly free a seated attendee's slot.

## Check-In Flow

`/events/{id}/checkin` (organizer-only, gated by `requireOrganizer` middleware): a single text
input for a pasted/typed `qrToken`. `internal/store/bookings.go`'s `CheckIn`:

- No match → `not_found`, no mutation.
- Match with `status: "checked_in"` → `already_checked_in`, no mutation (idempotent).
- Match with `status: "cancelled"` → `cancelled`, no mutation.
- Match with `status: "waitlisted"` → `waitlisted`, no mutation (a waitlisted guest cannot be
  checked in until promoted to confirmed).
- Match with `status: "confirmed"` → `PATCH` to `"checked_in"`, log a `checked_in` activity entry,
  render a success state with the attendee's name.

The result is rendered inline on the same page (not a PRG redirect), so the outcome message and
attendee name are never lost to a round-trip.

## UI Pages

- `/` - event list, auth-gated (`requireSignedIn`): paginated (`sort=startsAt`, page/limit=10),
  each card shows title/date/location + a live confirmed-vs-capacity indicator. Organizers see a
  "New event" call to action.
- `/events/new` - organizer-only create form (title, description, startsAt, location, capacity).
- `/events/{id}` - full detail: info, confirmed/capacity indicator, Book button for the current
  user if they are not that event's organizer and have no active booking, organizer-only
  Edit/Check-in/Delete affordances when `organizerId === session.user.id`, and the
  reverse-chronological activity feed for the event.
- `/events/{id}/edit` - organizer-only edit form.
- `/events/{id}/checkin` - organizer-only manual QR-token check-in.
- `/bookings` - the signed-in visitor's own bookings across all events, each rendered with a
  server-generated QR PNG of its `qrToken` and a Cancel action (confirmed/waitlisted only).
- `/login` - shared-account sign-in (also used for any newly registered account).
- `/register` - nice-to-have signup with an organizer/attendee role selector.

## Security Implementation

- Input validation: hand-written Go validation in each handler mirroring the reference web app's
  zod schemas exactly (`eventFormSchema`'s field caps: title/location 200 chars, description 2000
  chars, capacity 1-100000) - see `internal/server/handlers_events.go`'s `parseEventForm`.
- Authentication: Mudbase-issued JWT (access + refresh), stored only in an encrypted, httpOnly
  session cookie (`internal/session`) - never reaches any client-side script, since there is none.
  401 → refresh → retry handled once per call via request-context-threaded `TokenRefresher`.
- Authorization: enforced server-side by Mudbase's per-collection role permissions (verified live,
  see below); this app's own `requireOrganizer` middleware and `organizerId`/`userId` equality
  checks are defense-in-depth and UX gating, not the sole security boundary.
- Every `...Id` field used in a query filter is a real Mudbase ObjectId (session user ID or a
  fetched document's `_id`) - never a literal/placeholder string.
- Secrets: `SESSION_SECRET` (signs/encrypts the session cookie) is the only real secret this app
  holds; every Mudbase collection/project ID is a plain, non-secret identifier.

## Known Limitations / Design Decisions

- **No anonymous/public session** (see "Auth Flow") - matches the reference web app exactly.
- **Capacity accounting counts `"confirmed"` only, not `"checked_in"`** (see "Capacity-Race
  Handling Approach") - a deliberate reading of the task's literal spec, matching every sibling
  port of this showcase.
- **Reconciliation is a best-effort, non-transactional self-heal**, not a hard guarantee - an
  inherent property of building on a generic-CRUD BaaS with no cross-document transactions.
- **No push-based realtime** - no official Mudbase Go realtime client exists, and unlike the
  kanban port this app does not add a poll-refresh workaround, since none of this app's pages are
  a live shared-canvas UI the way a kanban board is.

## Live Smoke Test Results (2026-08-01, against the real project)

| Step | Result |
|---|---|
| `go build ./...` | clean |
| `go vet ./...` | clean |
| `gofmt -l .` | clean (no files listed) |
| Dev server starts, templates parse, `/login` `/register` render `200`, `/` redirects unauthenticated visitors to `/login` | ok |
| Static asset `/static/style.css` serves `200` | ok |
| Organizer login (`events.organizer.demo@gmail.com`) | `200`, `customRole: "organizer"` |
| Attendee login (`events.attendee.demo@gmail.com`) | `200`, `customRole: "attendee"` |
| App session cookie round-trips correctly for both roles (`/` shows correct name + role badge) | ok |
| Attendee `GET /events/new` (app middleware, organizer-only) | `303` redirect to `/` with "Only organizers can do that." - blocked before touching Mudbase |
| Organizer creates event via the app (capacity 2) | `303` → `/events/{id}` |
| Attendee views event detail, capacity shows `0 / 2 confirmed` | ok |
| **Booking #1** - attendee books via the app (0 confirmed so far) | decided `confirmed`, `booking_confirmed` logged |
| **Booking #2** - second app booking (1 confirmed so far) | decided `confirmed` (fills capacity), `booking_confirmed` logged |
| **Booking #3** - third app booking (2 confirmed, at capacity) | decided `waitlisted`, `booking_waitlisted` logged - capacity enforcement confirmed correct |
| **Cancellation** - attendee cancels booking #2 (a confirmed seat) via the app | `booking_cancelled` logged, reconciliation ran |
| Event capacity after cancellation | `2 / 2 confirmed` - booking #3 was promoted into the freed seat |
| Activity feed order after cancellation (`sort=-createdAt`) | `booking_promoted` → `booking_cancelled` → `booking_waitlisted` → `booking_confirmed` → `booking_confirmed` → `event_created` - exactly correct |
| **Check-in** - organizer checks in booking #1 by pasted `qrToken` | `200`, success flash "Aria Attendee checked in.", `checked_in` logged |
| Re-check-in the same booking (idempotency) | `200`, error flash "Aria Attendee is already checked in.", no mutation |
| Check in a **waitlisted** booking's `qrToken` | rejected: "This booking is waitlisted, not confirmed - it can't be checked in yet.", no mutation (verified unchanged afterward) |
| Check in a **cancelled** booking's `qrToken` | rejected: "This booking was cancelled.", no mutation |
| Check in a bogus/unknown `qrToken` | rejected: "No booking found for that check-in code." |
| Attendee `GET /events/{id}/checkin` (app middleware, organizer-only) | `303` redirect to `/` with "Only organizers can do that." |
| **RAW CURL, bypassing the app entirely** - fresh attendee JWT attempts `POST` (create) on `events` | `403 Insufficient permissions`, `{"required":{"action":"create","collection":"events"},"customRole":"attendee"}` |
| **RAW CURL** - same attendee JWT attempts `PATCH` (update) on the just-created event | `403 Insufficient permissions`, `action: "update"` |
| **RAW CURL** - same attendee JWT attempts `DELETE` on the event | `403 Insufficient permissions`, `action: "delete"` |
| **RAW CURL sanity check** - same attendee JWT reads the event (`GET`) | `200` - confirms the 403s above are role/action-specific, not a broken token |
| Cleanup - organizer deletes the test event via the app | `303` → `/`, subsequent `GET /events/{id}` redirects with "That event couldn't be found." |

**Net result**: the entire app-to-Mudbase contract - two-role auth with session cookies, capacity-
checked booking (confirmed vs. waitlisted), cancellation-triggered waitlist promotion, idempotent
QR-token check-in with every rejection branch (waitlisted/cancelled/not-found), and organizer-only
writes rejected server-side by Mudbase's own collection permissions independent of this app's own
route middleware - is proven correct against the real, live backend, both through the app's own
HTTP surface and via a raw `curl` request carrying a fresh attendee JWT that never touches this
app's code at all.

Note: the shared login-endpoint rate limit (5 requests / 15 min per IP, shared across every
concurrently-worked sibling project on this machine) was hit repeatedly during this session before
the two demo-account logins above succeeded; every other request used in this verification
(bookings, events, activity, check-in) goes through the separate, much less restrictive general
data-API limit and was unaffected.
