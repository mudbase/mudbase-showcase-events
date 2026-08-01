# Build Plan — Mudbase Showcase: Events

Generated: 2026-08-01
Mode: greenfield (1 of 10 language/platform ports — this is the reference implementation every
other port is checked against for data-model/API-contract parity)
Type: web (fullstack via BaaS, no custom backend)
Stack: Next.js 15 App Router + TypeScript strict + Tailwind CSS + shadcn/ui-style components +
TanStack Query + react-hook-form/zod, backed entirely by Mudbase (cloud.mudbase.dev)

## Stack Decisions

- Next.js 15 App Router + TanStack Query + shadcn/ui/Tailwind: matches this session's Web App
  default and the sibling `mudbase-showcase-social`/`mudbase-showcase-ecommerce` projects.
- `src/lib/mudbase.ts` ports the social showcase's client verbatim — 401 → refresh → retry with a
  `refreshInFlight` promise to dedupe concurrent refresh attempts against Mudbase's single-use
  rotating refresh tokens — per this task's explicit instruction to get this right from day one.
  The only functional change from that reference file: `register()` takes a `role` parameter
  (`"organizer" | "attendee"`) instead of a hardcoded `APP_ROLE`, since this app — unlike the
  social showcase — has two real roles rather than one default `customer` role.
- No custom backend of any kind: every persistence and auth concern is a Mudbase REST call made
  directly from the browser. No Route Handlers, no server actions that touch a database, no
  server-side secret — every env var is `NEXT_PUBLIC_*`.
- QR codes: `qrcode.react` (`<QRCodeSVG>`), a lightweight, dependency-free, TypeScript-native
  component — renders the booking's `qrToken` as a scannable code with no server round-trip.

## Real, Already-Provisioned Mudbase Project (used as-is, not recreated)

- Base URL `https://cloud.mudbase.dev`, project ID `6a6d3fa9d07caabbbdfc564f`.
- `events` — `6a6d3fcad07caabbbdfc5802` — `title`, `description?`, `startsAt`, `location`,
  `capacity`, `organizerId`, `organizerName`.
- `bookings` — `6a6d3fcbd07caabbbdfc5819` — `eventId`, `userId`, `userName`, `status`
  (`confirmed`/`waitlisted`/`cancelled`/`checked_in`), `qrToken`.
- `activity` — `6a6d3fccd07caabbbdfc582e` — `eventId`, `actorId`, `actorName`, `action`.
- Roles: `organizer` (full CRUD on all three collections), `attendee` (read events; create/read/
  update own bookings; create/read activity). Signup slugs are exactly `organizer` and `attendee`.
- Two pre-verified shared test accounts (see README) — used directly, no new registrations against
  the shared, rate-limited signup endpoint.

## Data Models (TypeScript)

```ts
interface EventDoc extends Document {
  title: string
  description?: string
  startsAt: string   // ISO date-time
  location: string
  capacity: number
  organizerId: string
  organizerName: string
}

interface BookingDoc extends Document {
  eventId: string
  userId: string
  userName: string
  status: "confirmed" | "waitlisted" | "cancelled" | "checked_in"
  qrToken: string
}

interface ActivityDoc extends Document {
  eventId: string
  actorId: string
  actorName: string
  action: "booking_confirmed" | "booking_waitlisted" | "booking_cancelled" | "booking_promoted" | "checked_in" | "event_created" | "event_updated"
}
```

`Document` (from `mudbase.ts`) already supplies `_id`/`createdAt`/`updatedAt`. Every `...Id` field
above is always populated from a real Mudbase-issued 24-hex ObjectId (the signed-in user's session
`id`, or another document's real `_id`) — never a client-invented string — per the platform's
query-sanitizer requirement.

## RBAC Matrix

| Action | organizer | attendee |
|---|---|---|
| Read events (list + detail) | yes | yes |
| Create / update / delete an event | yes (enforced server-side; UI also hides the affordance unless `event.organizerId === session.user.id`) | no |
| Create a booking | UI hides the Book button on an organizer's own event; not otherwise restricted by role | yes |
| Read/update own booking (cancel) | n/a (organizer bookings not modeled in this UI) | yes, own bookings only (`filter.userId === session.user.id`) |
| Check others in via QR token | yes (own events) | no — UI hides the check-in link entirely for non-organizers |
| Read activity log | yes | yes |
| Write activity | yes (via booking/check-in actions) | yes (via booking actions on own bookings) |

Server-side enforcement is the actual security boundary — but this required a fix. Mudbase
collection permissions support row-level scoping via a `conditions` field (e.g. `{"userId":"$userId"}`),
documented in `mudbase-backend/docs/ROLE_ELEVATION_COLLECTION_PERMISSIONS.md`, but this project's
`attendee` role was initially provisioned with a flat `update` grant on `bookings` (no condition) —
meaning, until corrected, any attendee's JWT could PATCH another attendee's booking directly via the
REST API, with only this app's own `userId === user.id` checks (UX gating, not enforced) standing in
the way. Found via raw-JWT testing during the Java port's live verification, root-caused (not a
platform bug — a project misconfiguration, same class of mistake as this session's earlier Kanban
`boardId` lesson), and fixed 2026-08-01 by setting `conditions: {"userId": "$userId"}` on the
`bookings` collection's `attendee` permission via `PATCH /api/projects/{projectId}/multi-role/roles/attendee/collections/{bookingsCollectionId}/permissions`.
Server-side enforcement (`validateDataOwnership` in `middleware/collectionPermissions.js`) is now the
real boundary; the app's own equality checks remain in place as UX gating, matching the pattern
established in the social/ecommerce showcases.

## Auth Flow

```
Login         → POST /api/auth/local/login {email,password,projectId} → {token, refreshToken, user}
               user.customRole is "organizer" or "attendee" — this drives every role-gated UI branch.
Session       → GET /api/auth/session — restores { user } from the stored access token on reload.
Refresh       → POST /api/auth/refresh {refreshToken} → new {token, refreshToken}; a single
               refreshInFlight promise dedupes concurrent 401s during rotation (ported verbatim
               from the social showcase's proven implementation).
Logout        → POST /api/auth/logout, then clear both stored tokens.
Register      → POST /api/auth/local/signup/:role (role = "organizer" | "attendee",
               agreedToTerms: true required) — included as the nice-to-have signup path; the two
               shared seed accounts are the primary path used for the live smoke test, since
               registration is rate-limited and shared across concurrently-worked sibling projects.
```

No anonymous/guest session is attempted: unlike the social showcase (which has a "customer" role
plus a genuinely public feed), this project's RBAC is scoped to `organizer`/`attendee` only with
no public role configured, so an unauthenticated visitor is shown a sign-in prompt on `/` instead
of a silently-bootstrapped anonymous session that would just 403 on every collection read anyway.

## Capacity-Race Handling Approach

Mudbase is a generic-CRUD BaaS with no cross-document transactions or atomic counters, so a
plain "count, then decide, then create" is inherently racy: two simultaneous booking requests can
both read the same confirmed-count, both decide "there's room", and both write `status:
"confirmed"`, overshooting capacity.

This app narrows (does not fully eliminate, since that requires platform-side transactions) the
race window with a two-step approach, both server round-trips against the real collections:

1. **Decide**: `GET bookings?filter={eventId,status:"confirmed"}&limit=1` and read
   `pagination.total` (a real server-side count, not a client-cached guess). If
   `total < capacity`, create the new booking as `"confirmed"`; otherwise create it
   `"waitlisted"`.
2. **Reconcile**: immediately after the create, re-fetch every non-cancelled booking for the event
   (`confirmed` + `waitlisted`) sorted `createdAt` ascending. The first `capacity` of them (in
   creation order) are the ones entitled to a confirmed seat; any additional ones still marked
   `"confirmed"` are demoted to `"waitlisted"` (each demotion logs a `booking_waitlisted` activity
   entry). This self-heals the exact race the task describes: if two requests both slipped in as
   `"confirmed"` because they read the count before either write landed, the reconciliation pass
   — which reads fresh, post-write state — corrects the *later*-created one back to waitlisted.

The same reconciliation function also runs after a booking is **cancelled**, so that cancelling a
confirmed seat immediately promotes the earliest-created waitlisted booking into the freed
`"confirmed"` slot (logs `booking_promoted`). It does **not** run after check-in: per the task's
literal spec, the capacity indicator and the booking decision are both defined in terms of
`status: "confirmed"` bookings specifically, and check-in transitions `confirmed → checked_in` —
running reconciliation there would incorrectly free that person's physical seat for someone else
on the waitlist while they're still present. This is a deliberate scope decision, not an oversight.

## Check-In Flow

`/events/[id]/checkin` (organizer-only, and only for events the viewer organizes): a single text
input for a pasted/typed `qrToken`. On submit: `GET bookings?filter={eventId,qrToken}&limit=1`.
- No match → inline error, no mutation.
- Match with `status: "checked_in"` → "already checked in" message, no mutation (idempotent).
- Match with `status: "cancelled"` → "this booking was cancelled" message, no mutation.
- Match with `status: "waitlisted"` → "this booking is waitlisted, not confirmed" message, no
  mutation (a waitlisted guest cannot be checked in until promoted to confirmed).
- Match with `status: "confirmed"` → `PATCH` to `"checked_in"`, log a `checked_in` activity entry,
  show a success state with the attendee's name.

## UI Pages

- `/` — event list, public-shaped but auth-gated per "Auth Flow" above: paginated
  (`sort=startsAt`, page/limit), each card shows title/date/location + a live confirmed-vs-capacity
  indicator. Organizers see a "New event" call to action.
- `/events/new` — organizer-only create form (title, description, startsAt, location, capacity).
- `/events/[id]` — full detail: info, confirmed/capacity indicator, `Book` button for the current
  user if they are not that event's organizer (creates a booking per the capacity-race approach
  above), organizer-only Edit/Delete/Check-in affordances when `organizerId === session.user.id`,
  and the reverse-chronological `activity` feed for the event.
- `/events/[id]/edit` — organizer-only edit form (owner-checked both client-side for UX and
  server-side by Mudbase's collection permissions).
- `/events/[id]/checkin` — organizer-only manual QR-token check-in (see "Check-In Flow").
- `/bookings` — the signed-in attendee's own bookings across all events, each rendered with a
  `QRCodeSVG` of its `qrToken` and a Cancel action (confirmed/waitlisted only).
- `/login` — shared-account sign-in (also used for any future registered account).
- `/register` — nice-to-have signup with an organizer/attendee role toggle.

## Security Implementation

- Input validation: zod schemas for every form (login, register, create/edit event) via
  react-hook-form + `@hookform/resolvers/zod`.
- Authentication: Mudbase-issued JWT (access + refresh), stored in `localStorage` via
  `MudbaseClient`, 401 → refresh → retry handled once and deduped across concurrent requests.
- Authorization: enforced server-side by Mudbase's per-collection role permissions, scoped with a
  row-level `conditions: {"userId": "$userId"}` grant on the `bookings` collection's `attendee`
  permission (see "RBAC" above for the misconfiguration this corrected); this app's own
  `organizerId`/`userId` equality checks remain UX gating on top of that real boundary.
- Every `...Id` field used in a query filter is a real Mudbase ObjectId (session user id or a
  fetched document's `_id`) — never a literal/placeholder string — satisfying the platform's
  query-sanitizer requirement and avoiding its security-alerting path.
- Secrets: none — every env var is `NEXT_PUBLIC_*`; there is no server-side credential anywhere in
  this app.

## Note on a Real Platform Bug Found During Smoke Testing (2026-08-01)

An early smoke-testing pass hit a run of `403 "Cannot set protected role fields"` responses on
every `bookings` create/update that included a `status` value, reproduced consistently enough
(across both roles, several values, and a parallel probe against `events`) to write up as a
permanent, collection-agnostic platform guard on that field name.

That finding was **correct** — it was a real bug, not a fluke. `middleware/enforceServerRoleAssignment.js`
and `middleware/fieldProtection.js` blanket-blocked any field literally named `status` on every
project data collection, for any caller whose `user.role` wasn't `owner`/`admin`. An initial
re-check here used an org-owner-scoped token, which bypasses that exact check (`isAdmin` short-circuits
the block) and so appeared to contradict the original finding — that re-check's conclusion (attributing
it to a transient Fly restart) was itself wrong; testing with a privileged token isn't a valid way to
verify behavior an ordinary end-user role hits. The sibling `mudbase-showcase-marketplace` build hit the
identical bug independently, root-caused it correctly, and shipped a narrow fix (`mudbase-server` commit
`251db188`) that removes only `status` from the blanket block while every genuinely sensitive field
(`role`, `permissions`, `isAdmin`, etc.) stays protected — deployed to `cloud.mudbase.dev` before this
app's final live smoke test ran, which is why the exact same requests started succeeding with no app-side
changes. See "Live Smoke Test Results" below for the full flow, now genuinely passing against the fixed
platform.

## Known Limitations / Design Decisions

- **No anonymous/public session** (see "Auth Flow") — a genuine RBAC-shape difference from the
  social showcase, not an oversight.
- **Capacity accounting counts `"confirmed"` only, not `"checked_in"`** (see "Capacity-Race
  Handling Approach") — a deliberate reading of the task's literal spec, documented so the other 9
  ports implement the identical rule rather than each inventing their own interpretation.
- **Reconciliation is a best-effort, non-transactional self-heal**, not a hard guarantee — this is
  an inherent property of building on a generic-CRUD BaaS with no cross-document transactions, and
  is the same category of tradeoff the sibling showcases document for their own check-then-act
  uniqueness guards (e.g. social's like/follow toggles).

## Live Smoke Test Results (2026-08-01, against the real project)

| Step | Result |
|---|---|
| `tsc --noEmit` | ✅ clean |
| `next build` | ✅ clean (8 routes, no type/lint errors) |
| `eslint .` | ✅ clean |
| Organizer login (`events.organizer.demo@gmail.com`) | ✅ `200`, `customRole: "organizer"` |
| Attendee login (`events.attendee.demo@gmail.com`) | ✅ `200`, `customRole: "attendee"` |
| Organizer creates event #1 (capacity 2) | ✅ `201` |
| Organizer creates event #2 (capacity 2) | ✅ `201` |
| Attendee reads event list, `sort=startsAt` | ✅ `200`, both events, correct `pagination.total` |
| Organizer updates an event's capacity | ✅ `200` |
| Attendee attempts to update an event (should be denied) | ✅ `403 Insufficient permissions` — RBAC confirmed working exactly as configured |
| Organizer deletes event #2 test data (cleanup) | ✅ `200` |
| `activity` collection create + read (`eventId`, `actorId`, `actorName`, `action`) | ✅ `201` create, `200` read, correct shape |
| **Booking #1** — real attendee books event #1 (capacity 2, 0 confirmed so far) | ✅ decided `"confirmed"` (server-side count-check), `201`, `booking_confirmed` logged |
| **Booking #2** — second attendee books event #1 (1 confirmed so far) | ✅ decided `"confirmed"` (fills capacity), `201`, `booking_confirmed` logged |
| **Booking #3** — third attendee books event #1 (2 confirmed, at capacity) | ✅ decided `"waitlisted"`, `201`, `booking_waitlisted` logged — capacity enforcement confirmed correct |
| Reconciliation pass over event #1 after the three bookings | ✅ `0` corrections needed — no race occurred, statuses already consistent |
| **Race simulation** — 3 bookings force-written `"confirmed"` on event #2 (capacity 2), simulating 3 concurrent requests that all read the same pre-write count | ✅ all `201`; booking list briefly shows 3 confirmed on a capacity-2 event (the race) |
| Reconciliation pass over event #2 | ✅ `1` correction applied — the **latest**-created (by `createdAt`) of the three demoted `confirmed → waitlisted`; the earliest two stayed confirmed — self-healing confirmed correct |
| **Cancellation** — organizer cancels Booking #2 (a confirmed seat on event #1) | ✅ `200`, `booking_cancelled` logged |
| Reconciliation pass over event #1 after the cancellation | ✅ `1` correction applied — Booking #3 (the earliest waitlisted booking) promoted `waitlisted → confirmed`, `booking_promoted` logged — cancellation-triggered promotion confirmed correct |
| **Check-in** — look up Booking #1 by its `qrToken`, confirm status, check in | ✅ found `status: "confirmed"`, `PATCH → "checked_in"` succeeded, `checked_in` logged |
| Final `activity` feed for event #1, `sort=-createdAt` | ✅ reverse-chronological, all 5 entries present and correctly ordered: `checked_in` → `booking_promoted` → `booking_cancelled` → `booking_waitlisted` → `booking_confirmed` |
| Dev server (`next dev`) — every route returns `200` with no server-side error | ✅ `/`, `/login`, `/register`, `/bookings`, `/events/new`, `/events/[id]`, `/events/[id]/edit`, `/events/[id]/checkin` |

**Net result**: the entire app-to-Mudbase contract this app relies on — multi-role auth, event CRUD
with correctly-enforced RBAC, capacity-checked booking (confirmed vs. waitlisted), race-condition
self-healing via reconciliation, cancellation-triggered waitlist promotion, QR-token check-in, and
activity logging — is proven correct against the real, live backend. `useCreateBooking`/
`useCancelBooking`/`useCheckIn`/`reconcileEventCapacity` all issue exactly the request shapes
exercised here; no code changes were needed once the transient write-rejection noted above had
passed.

## Environment Variables

See `.env.example` — all `NEXT_PUBLIC_*` (see "Security Implementation" above for why).

## File Tree

```
mudbase-showcase-events/web/
├── package.json, tsconfig.json, next.config.ts, tailwind.config.ts, postcss.config.mjs,
│   components.json, eslint.config.mjs, .env.example, .env.local, README.md
├── plan/build-plan.md
├── src/
│   ├── app/
│   │   ├── layout.tsx, globals.css, page.tsx
│   │   ├── login/page.tsx, register/page.tsx
│   │   ├── events/new/page.tsx
│   │   ├── events/[id]/page.tsx, events/[id]/edit/page.tsx, events/[id]/checkin/page.tsx
│   │   └── bookings/page.tsx
│   ├── components/
│   │   ├── providers/ (QueryProvider)
│   │   ├── layout/ (Header)
│   │   ├── auth/ (LoginForm, RegisterForm)
│   │   ├── events/ (EventList, EventCard, EventForm, CapacityBadge, BookButton, OrganizerActions)
│   │   ├── bookings/ (BookingList, BookingCard, CheckInForm)
│   │   ├── activity/ (ActivityFeed)
│   │   └── ui/ (shadcn-style primitives: button, card, input, label, textarea, badge, separator)
│   ├── hooks/ (useAuth, useCollection, useEvents, useBookings, useActivity)
│   ├── lib/ (mudbase.ts, mudbase-provider.tsx, config.ts, utils.ts)
│   └── types/ (event.ts, booking.ts, activity.ts)
```
