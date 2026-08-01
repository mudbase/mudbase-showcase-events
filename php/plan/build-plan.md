# Build Plan — Mudbase Showcase: Events (PHP port)

Generated: 2026-08-01
Mode: PHP reimplementation of the reference Next.js app in `../web` — read that project's
`plan/build-plan.md`, `src/lib/capacity.ts`, and `src/hooks/useBookings.ts` first; those are the
canonical data model, RBAC matrix, and capacity/waitlist-promotion algorithm this port mirrors
line-for-line. This file only records what's specific to the PHP port.
Type: web (server-rendered, zero client JavaScript), backed entirely by Mudbase (cloud.mudbase.dev)
Stack: Plain PHP 8.1+ (no framework), PHP's built-in dev server for local development, the real
generated `mudbase/sdk` Composer package — same architecture as the sibling
`mudbase-showcase-kanban/php` port: `Router` → `Controllers` → `View` + plain `.php` view files, a
request-scoped `AppContext`, a `MudbaseClient` wrapper around the SDK.

## Stack Decisions

- Mirrors `mudbase-showcase-kanban/php`'s architecture file-for-file where the domain allows it:
  `src/Router.php`, `src/View.php`, `src/Config.php`, `src/bootstrap.php`, `src/Http/*`,
  `src/Mudbase/*` are near-verbatim ports (see each file's docblock for the few real deltas).
- Auth is session-based: the Mudbase JWT pair lives in native PHP `$_SESSION`, not `localStorage`.
  No client-side JavaScript auth flow, and in fact **no client-side JavaScript at all** — every
  interaction is a plain HTML `<form>` POST, and inline disclosures (delete confirmation) use
  native `<details>/<summary>` instead of a JS-toggled modal.
- QR codes: the reference app renders a real scannable `<QRCodeSVG>` client-side
  (`qrcode.react`). A PHP server-rendered page with zero client JS cannot run a JS QR library, so
  this port renders the QR image via a plain `<img src="https://api.qrserver.com/v1/create-qr-code/...">`
  — the browser just loads an image, no script executes. The functional path (the thing the
  check-in flow actually verifies) is the plain-text `qrToken` printed alongside it, matching the
  check-in form's own "paste or type the scanned code" model — the visual QR is a nice-to-have,
  not the mechanism under test.
- `src/Support/PseudoId.php` is carried over from the kanban port for architectural parity across
  the showcase family (djb2-hash pseudo-ObjectId for a free-typed name with no backing document),
  but this app's data model has no field that needs it — every `...Id` field
  (`organizerId`/`userId`/`eventId`) is always a real signed-in user id or a fetched document's
  real `_id`. It is fully implemented and verified against the reference algorithm, but not called
  from any controller — see that file's docblock for the full rationale.

## Real, Already-Provisioned Mudbase Project (used as-is, not recreated)

- Base URL `https://cloud.mudbase.dev`, project ID `6a6d3fa9d07caabbbdfc564f`.
- `events` — `6a6d3fcad07caabbbdfc5802` — `title`, `description?`, `startsAt`, `location`,
  `capacity`, `organizerId`, `organizerName`.
- `bookings` — `6a6d3fcbd07caabbbdfc5819` — `eventId`, `userId`, `userName`, `status`
  (`confirmed`/`waitlisted`/`cancelled`/`checked_in`), `qrToken`.
- `activity` — `6a6d3fccd07caabbbdfc582e` — `eventId`, `actorId`, `actorName`, `action`.
- Roles: `organizer` (full CRUD on all three collections), `attendee` (read events; create/read/
  update own bookings; create/read activity). Two pre-verified shared demo accounts (see README).

## RBAC Matrix

Identical to the reference app's (see `../web/plan/build-plan.md` "RBAC Matrix") — reproduced here
for this port's own read-only convenience:

| Action | organizer | attendee |
|---|---|---|
| Read events (list + detail) | yes | yes |
| Create / update / delete an event | yes (enforced server-side; UI also hides the affordance unless `event.organizerId === session.user.id`) | no |
| Create a booking | UI hides the Book button on an organizer's own event | yes |
| Read/update own booking (cancel) | n/a | yes, own bookings only |
| Check others in via QR token | yes (own events; UI hides the check-in link entirely for non-organizers) | no |
| Read activity log | yes | yes |
| Write activity | yes (via booking/check-in actions) | yes (via booking actions on own bookings) |

`src/Support/Rbac.php` mirrors this matrix purely to hide/disable controls a role or non-owner
shouldn't see — it is **never** consulted before a write in any controller. Every mutating
controller method (`EventController::create/update/delete/checkin`, `BookingController::create/
cancel`) calls the same `MudbaseClient` write a permitted role would use and lets Mudbase's own
collection permissions return the real `403` if the signed-in role/ownership isn't allowed. See
"Live Smoke Test Results" below for the raw-request proof of this boundary.

## Auth Flow

```
Login    → POST /api/auth/local/login {email,password,projectId} → {token, refreshToken, user}
           user.customRole is "organizer" or "attendee" — this drives every role-gated view branch.
Session  → GET /api/auth/local/session — the source of truth for the current user, fetched right
           after login and cached in $_SESSION for the rest of the session.
Refresh  → POST /api/auth/refresh — MudbaseClient retries exactly once on a 401, silently, and
           persists the rotated pair back into $_SESSION via a callback wired in bootstrap.php.
Logout   → POST /api/auth/logout, then clear $_SESSION.
```

No registration UI, no anonymous/guest session — matching the reference app's own "Auth Flow"
section: this project's RBAC has no public role configured, so an unauthenticated visitor is
bounced to `/login` by `AppContext::requireSignIn()` (called first thing by every controller
method except `AuthController`).

## Capacity-Race Handling Approach

Ported line-for-line from the reference app's `reconcileEventCapacity` (`../web/src/lib/capacity.ts`)
into `src/Support/CapacityReconciler.php` — same two-step decide-then-reconcile approach:

1. **Decide**: `GET bookings?filter={eventId,status:"confirmed"}&limit=1`, read `pagination.total`.
   If `total < capacity`, create the booking `"confirmed"`; otherwise `"waitlisted"`.
2. **Reconcile**: immediately after, re-fetch every non-cancelled booking for the event
   (confirmed + waitlisted) sorted `createdAt` ascending. The first `capacity` of them (creation
   order) are entitled to a seat; any others still `"confirmed"` are demoted to `"waitlisted"`
   (logs `booking_waitlisted`). Runs again after a **cancellation**, promoting the earliest
   waitlisted booking into the freed seat (logs `booking_promoted`). Does **not** run after
   check-in, for the same reason the reference app documents: capacity is defined in terms of
   `"confirmed"` bookings specifically, and reconciling post-check-in would incorrectly free an
   already-seated attendee's slot.

One PHP-specific addition: `MudbaseClient::listAllDocuments()`. The generated SDK's `DataApi`
client-side caps any single request at `limit=100` (confirmed by reading the generated source —
not a server constraint this app can query around), but the reference app's browser-side
`client.getDocuments()` has no such cap and reads up to 1000 rows in one request for
reconciliation. `listAllDocuments()` transparently paginates the 100-row SDK cap up to the same
1000-row ceiling so `CapacityReconciler` preserves the reference's effective behavior rather than
silently truncating at 100 confirmed+waitlisted bookings per event.

## Check-In Flow

`/events/{id}/checkin` (organizer-only affordance; UI hides the link for non-owners, but the route
itself is reachable by anyone signed in — the write it triggers is what Mudbase actually gates).
A single text input for a pasted/typed `qrToken`. Every outcome — not found, already checked in,
cancelled, waitlisted, or a successful check-in — is delivered as a flash message on the redirect
back to the same page (`Http/Flash.php`), reusing this app's existing POST → flash → redirect
(PRG) pattern instead of introducing a second one-off "render inline result" path.

One subtlety carried over exactly from the reference app's `useCheckIn`: the `checked_in` activity
row logs the **booking's own** `userId`/`userName` as the actor, not the organizer's — "{name}
checked in" describes the guest, even though the organizer's account is the one making the write.

## UI Pages

- `/` — event list, auth-gated, paginated (`sort=startsAt`, page/limit 10), each card shows a live
  confirmed-vs-capacity badge. Organizers see a "New event" call to action.
- `/events/new`, `/events/{id}/edit` — organizer-affordance create/edit form (title, description,
  `datetime-local` start, location, capacity) — same field limits as the reference's zod schema.
- `/events/{id}` — full detail, Book button (or booking status) for non-owners, organizer-only
  Edit/Check-in/Delete affordances (Delete behind a native `<details>` confirmation, no JS
  `confirm()`), and the reverse-chronological `activity` feed for the event.
- `/events/{id}/checkin` — organizer-affordance manual QR-token check-in.
- `/bookings` — the signed-in user's own bookings across all events, each with a QR image + the
  plain-text `qrToken`, and a Cancel action (confirmed/waitlisted only).
- `/login` — two one-click demo-account forms (no client JS — real hidden-input forms) plus a
  manual email/password form.

## Security Implementation

- CSRF token (`Http/Csrf.php`) on every state-changing form, verified before any controller logic
  runs.
- Open-redirect guard (`Response::redirectToSafe()`) on the login `redirectTo` value.
- Session id regenerated on every privilege change (sign-in, sign-out).
- Authorization is enforced server-side by Mudbase's per-collection role permissions; this app's
  own `organizerId`/`userId` equality checks (`Rbac::canManageOwnEvent()`) are UX gating only —
  see "RBAC Matrix" above and the live proof below.
- Every `...Id` field used in a query filter or write is a real Mudbase ObjectId (session user id,
  or a fetched document's `_id`) — never a literal/placeholder string.
- Secrets: the Mudbase project id and collection ids live in `.env` (server-side only, never
  rendered to the page) — this app has a real server process (unlike the reference Next.js app,
  which is entirely `NEXT_PUBLIC_*`), so these values are not client-exposed at all.

## Known Platform Facts (carried over, not rediscovered)

- `status` field writes are **not** blocked — the blanket `middleware/fieldProtection.js`
  guard that used to reject any field literally named `status` for non-admin roles was fixed in
  `mudbase-server` commit `251db188` (see `../web/plan/build-plan.md` for the full incident
  writeup) and has been deployed to `cloud.mudbase.dev` since before this port was built.
- Any `...Id`-suffixed query filter field must be a real 24-char hex ObjectId — confirmed
  repeatedly across every showcase PHP port to date.
- The demo accounts (`events.organizer.demo@gmail.com` / `events.attendee.demo@gmail.com`) are
  shared across every concurrent sibling-language port of this same showcase (Go, Python, Ruby,
  Flutter, Expo, ...) being built in parallel — `/api/auth/local/login` is rate-limited per-IP,
  and since every one of those ports runs from the same development machine (same egress IP), a
  burst of concurrent login attempts across languages can and did exhaust that shared budget
  during this port's own live smoke test — see "Live Smoke Test Results" below.

## Known Limitations / Design Decisions

- **No cascade delete of a deleted event's bookings/activity rows** — matches the reference app's
  own `useDeleteEvent` (a bare document delete, no cleanup), not a gap introduced by this port.
- **No realtime** — the reference Next.js app has no Socket.IO subscriptions on this project
  either (unlike the kanban showcase), so there's no realtime feature to lose in translation; every
  mutation already redirects (PRG) to a fresh page load showing current state.
- **QR image is a third-party `<img>` fetch** (`api.qrserver.com`), not a server-generated
  scannable barcode — see "Stack Decisions" above for why, and note the plain-text `qrToken` next
  to it is the functionally-relevant value for this demo's check-in flow either way.
- **`src/Support/PseudoId.php` has no call site in this app** — see "Stack Decisions" above.

## Live Smoke Test Results (2026-08-01, against the real project)

| Step | Result |
|---|---|
| `php -l` on every `.php` file | ✅ clean |
| `composer install` (path-repo `mudbase/sdk`) | ✅ clean |
| Organizer login (`events.organizer.demo@gmail.com`) | ✅ `303`→home, `customRole: "organizer"` confirmed via rendered role badge |
| Organizer creates event ("PHP Port Test Event", capacity 2) | ✅ `303`→`/events/{id}`, event detail renders correctly |
| Event list (`/`) shows the new event with a live `0/2 booked` capacity badge | ✅ confirmed, alongside several other events already present from concurrent sibling-language test runs sharing this project |
| Organizer edits the event (title/description/startsAt/location/capacity) | ✅ `303`→detail, all fields updated, `event_updated` activity logged |
| Attendee login (`events.attendee.demo@gmail.com`) | ⚠️ hit the shared cross-language rate limit on `/api/auth/local/login` for ~30 minutes real wall-clock time (six sibling PHP/Go/Python/Ruby/Swift/C#/Expo/Flutter ports of this same showcase were being built concurrently against the same two demo accounts from the same egress IP) — resolved by a bounded retry loop (90s spacing, 14-attempt cap) that succeeded on attempt 7; see "Known Platform Facts" |
| Attendee views event list + detail | ✅ `200`, correct role badge ("Attendee"), Book button shown (not organizer's own event) |
| **Booking creation** — attendee books a fresh capacity-1 test event | ✅ decided `"confirmed"` (0 confirmed so far), flash "You're confirmed!", capacity badge flips to `Full · 1/1`, `booking_confirmed` activity logged |
| **QR check-in** — organizer submits the booking's real `qrToken` on `/events/{id}/checkin` | ✅ booking `confirmed → checked_in`, flash "Aria Attendee is checked in.", `checked_in` activity logged with the **attendee's own** `userId`/`userName` as actor (matching the reference app's `useCheckIn` exactly, not the organizer's) |
| **Idempotent re-check-in** — same `qrToken` submitted again | ✅ no mutation, flash "Aria Attendee was already checked in." |
| **Check-in, not-found case** — a bogus `qrToken` | ✅ no mutation, flash "No booking found for this code at this event." |
| **Check-in, CSRF rejection** — wrong `_csrf` value | ✅ no mutation, flash "Your session expired — please try again." |
| **Booking cancellation** — attendee books a second capacity-2 test event, then cancels it | ✅ `booking_cancelled` logged, `CapacityReconciler` ran (no-op — no waitlisted bookings to promote), capacity badge reverts to `0/2 booked`, Book button reappears on the event page |
| 404 handling — an unregistered route | ✅ `404`, "Page not found" |
| 404 handling — a well-formed but non-existent event id | ✅ redirects to `/`, flash "That event no longer exists." |
| Logout with an invalid CSRF token | ✅ rejected, session remains signed in (flash "Your session expired") |
| `/bookings` renders real confirmed bookings (from concurrent sibling runs sharing the organizer demo account) with QR image + plain-text token + status badge | ✅ confirmed — proves `partials/booking_card.php` renders real, not just self-created, data correctly |

### Raw, controller-independent RBAC proof against `cloud.mudbase.dev`

A real attendee JWT was extracted via a temporary debug route (`GET /__debug_token`, dumping
`$_SESSION['mudbase_token']` as plain text), added to `public/index.php` immediately before this
test and **deleted immediately after** — confirmed via `grep -rn "debug_token\|DEBUG-TEMP"` across
the whole `php/` tree returning no matches before committing.

| Raw request (attendee JWT, bypassing this app's controllers entirely) | Result |
|---|---|
| `POST /api/data/projects/{id}/collections/events/data` (create an event — organizer-only) | ✅ **`403`** — `{"error":"Insufficient permissions","required":{"action":"create","collection":"events"},"userRole":"viewer","customRole":"attendee"}` |
| `DELETE /api/data/projects/{id}/collections/events/data/{eventId}` (delete an event — organizer-only) | ✅ **`403`** — `{"error":"Insufficient permissions","required":{"action":"delete","collection":"events"},"userRole":"viewer","customRole":"attendee"}` |
| Positive control: `POST /api/data/projects/{id}/collections/bookings/data` (create a booking — attendee-permitted) with the **same JWT** | ✅ **`201`** — proves the JWT itself is valid and live, and that the 403s above are a genuine role check, not a broken/expired token producing a blanket rejection |
| Cleanup: `PATCH` the raw-test booking to `status: "cancelled"` | ✅ `200` — no test debris left `"confirmed"` in the shared collection |

**Net result**: Mudbase's own collection permissions are the real security boundary for this app,
exactly as `src/Controllers/EventController.php`'s docblock claims — an attendee-role JWT is
genuinely rejected server-side on organizer-only writes, independent of anything this PHP app's
controllers or views do. This mirrors the identical proof already on record in the reference
Next.js app's own `plan/build-plan.md` ("Attendee attempts to update an event... `403`") against
this same live project.
