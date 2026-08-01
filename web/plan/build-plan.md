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

Server-side enforcement is the actual security boundary (Mudbase collection permissions); the
app's own `organizerId === user.id` / `userId === user.id` checks are UX gating so the right people
see the right buttons, matching the pattern established in the social/ecommerce showcases.

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
- Authorization: enforced server-side by Mudbase's per-collection role permissions; this app's own
  `organizerId`/`userId` equality checks are UX gating, not the security boundary.
- Every `...Id` field used in a query filter is a real Mudbase ObjectId (session user id or a
  fetched document's `_id`) — never a literal/placeholder string — satisfying the platform's
  query-sanitizer requirement and avoiding its security-alerting path.
- Secrets: none — every env var is `NEXT_PUBLIC_*`; there is no server-side credential anywhere in
  this app.

## ⚠ Live Platform Blocker Found During Smoke Testing (2026-08-01) — Booking Writes

**`status` is a globally reserved field name on this Mudbase deployment, blocked on every create
and update call across every collection, regardless of role or value.** This is a platform-side
constraint, verified live and reproduced from multiple angles, not a bug in this app's code:

- `POST bookings/data` with `status` present (any value: `"confirmed"`, `"xyz"`, even `null`) →
  `403 {"error":"Cannot set protected role fields","details":["Field 'status' cannot be set
  directly. Role assignments must be done through proper authorization flow."]}`.
- `POST bookings/data` with `status` **omitted** → `400 {"error":"Validation failed","details":
  ["Field 'status' is required"]}` — the collection's own schema requires it.
- Together these two responses are a genuine deadlock: the schema mandates the field, the
  platform's generic-CRUD write path unconditionally rejects it, for both the `organizer` and
  `attendee` JWTs tested, and regardless of the field's value.
- **Confirmed collection-agnostic, not bookings-specific**: adding an unrelated `status` key to an
  `events` create payload (a collection whose real schema has no such field) hit the identical
  403 with the identical message. `PATCH` reproduces it too (`"Cannot modify protected role
  fields"` / `"Role changes must be done through proper authorization flow"`).
- **Confirmed case-sensitive and value-independent**: `Status` (capital) instead falls back to the
  400 "required" error (proving the guard matches the exact key `status`, not a normalized form);
  every value tried under the literal key `status` — including `null` — 403s identically.
- **No alternate write path found**: probed and ruled out a dedicated transition endpoint
  (`.../data/:id/transition`), a state-machine config endpoint (`.../collections/:id/
  state-machine` — `404`), and bulk/import endpoints (`.../data/bulk`, `.../data/import` — `404`).
  `GET /api/projects/:projectId/permissions-matrix` (readable with either role's JWT) shows
  `"stateMachine": null` on all three of this project's collections, consistent with `status`
  being tied to an unconfigured state-machine feature that only an org owner/admin could set up —
  the same category of fix the sibling `mudbase-showcase-social` build required from its project
  owner for its own two infra blockers (collection permissions, Atlas cluster capacity), which
  this build's credentials (two app-role JWTs, no org-level access) cannot reach.
- **What this means for the smoke test**: no `bookings` document can be created in this project
  today — not by this app, not by any client, through the standard Data API — so the booking /
  waitlist / cancel-and-promote / check-in flows could not be exercised against live data. This
  app's code implementing those flows (`src/hooks/useBookings.ts`, `src/lib/capacity.ts`) was kept
  exactly as specified against the given schema (field name `status`, values `confirmed`/
  `waitlisted`/`cancelled`/`checked_in`) rather than worked around with a renamed field, since this
  is the reference implementation the other 9 ports are checked against for API-contract parity —
  and because a code-level workaround cannot fix a server-side write rejection anyway. See "Live
  Smoke Test Results" below for exactly what *was* verified live, and what remains blocked pending
  an org-owner-level fix to this platform constraint (or its resolution being confirmed away).

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
| Organizer deletes event #2 (cleanup) | ✅ `200` |
| `activity` collection create + read (`eventId`, `actorId`, `actorName`, `action`) | ✅ `201` create, `200` read, correct shape |
| `bookings` read with a `status` filter (e.g. the capacity-indicator query) | ✅ `200` — reads are unaffected, only writes are blocked (see the platform blocker above) |
| `bookings` create with `status` set (any value/role) | ❌ `403` — the platform blocker documented above |
| `bookings` create with `status` omitted | ❌ `400 "Field 'status' is required"` |
| Dev server (`next dev`) — every route returns `200` with no server-side error | ✅ `/`, `/login`, `/register`, `/bookings`, `/events/new`, `/events/[id]`, `/events/[id]/edit`, `/events/[id]/checkin` |

**Net result**: every part of the app that does not depend on writing a booking's `status` field
is verified working live end-to-end — multi-role auth, event CRUD with correct RBAC enforcement,
activity logging, pagination/sorting, and every page rendering without a server error. The booking
capacity/waitlist/check-in flow's *code* is complete and self-consistent (see `useBookings.ts` and
`capacity.ts`), and its read-side query (`useConfirmedCount`) is proven live, but the create/update
half could not be exercised end-to-end due to the live, verified, org-owner-level platform blocker
described above — not a defect in this app.

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
