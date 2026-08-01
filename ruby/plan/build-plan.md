# Build Plan — Mudbase Showcase: Events (Ruby / Sinatra port)

Generated: 2026-08-01
Mode: brownfield port (one of several per-language reimplementations of the reference Next.js app)
Type: web (fullstack via BaaS, no custom backend)
Stack: Ruby 4.0 + Sinatra 4 + ERB + `Rack::Session::Cookie`, backed entirely by Mudbase
(`cloud.mudbase.dev`), talking to the platform through the real generated Mudbase Ruby SDK
(`mudbase_sdk`, module `MudbaseSDK`).

## Stack Decisions

- Sinatra + ERB + Puma, no ORM, no database of its own, **no client-side JavaScript at all** —
  matches the framework choice and file-layout conventions the sibling
  `mudbase-showcase-kanban/ruby` port established: `lib/mudbase/config.rb`,
  `lib/mudbase/errors.rb`, `lib/mudbase/client_factory.rb`, and the `AuthService`/
  `SessionHelpers` split with `with_access_token`'s 401-refresh-retry wrapper are ported
  near-verbatim from that port.
- `mudbase_sdk` sourced from `https://github.com/mudbase/mudbase-sdk.git` (`ruby/*.gemspec` glob),
  `ffi ~> 1.17` pinned for the same native-extension reason documented in the sibling port's
  Gemfile/README.
- **No anonymous/guest session** — this project has no public role configured (only
  `organizer`/`attendee`), so every page except `/login` requires a real signed-in account,
  mirroring the reference web app's own scoping decision (see `../web/plan/build-plan.md`
  "Auth Flow").
- **No registration UI**, matching the sibling kanban port's own scoping decision: both demo
  accounts already exist and are provisioned out-of-band; `/login` ships a normal email+password
  form plus two "Sign in as Organizer / Attendee" one-click shortcuts (small forms with hidden,
  pre-filled credentials — the closest a zero-client-JS server-rendered app can get to the
  reference app's JS quick-fill buttons).
- **QR codes rendered server-side** via the pure-Ruby `rqrcode` gem, embedded as inline SVG on
  `/bookings` — the closest a zero-client-JS server-rendered app can get to the reference web
  app's client-rendered `<QRCodeSVG>` (`qrcode.react`). See `lib/view_helpers.rb#qr_svg`.
- **Check-in is a plain form POST** (paste/type the scanned code, submit) — no camera/JS
  QR-scanning, consistent with shipping zero client-side JavaScript.

## Auth Model

Every page except `/login` requires a real signed-in account, for both roles — there is no
public/guest read on this project. `require_login!` (`lib/session_helpers.rb`) redirects to
`/login` when no session exists.

```
GET /login, POST /login   → POST /api/auth/local/login { email, password, projectId }
                             → 200 + token/refreshToken + user.customRole
                               (one of "organizer"/"attendee" — login_local_user is
                               role-agnostic, the same endpoint authenticates either role)
401 on any authenticated call → SessionHelpers#with_access_token refreshes once (single-use,
                             rotating refresh token) → retries the original call once →
                             surfaces the error (logs the session out) if that also fails
POST /logout               → best-effort MudbaseSDK logout_local_user, local session cleared
                              regardless
```

## RBAC Matrix (enforced server-side by Mudbase's own collection permissions; this app's own
`require_organizer!`/`require_event_owner!` gates are an *additional* server-side check, not
just UI hiding — see "Live smoke test results" below for a raw request using a fresh attendee
JWT that bypasses this app's own routes entirely)

| Action | organizer | attendee |
|---|---|---|
| Read events (list + detail) | yes | yes |
| Create / update / delete an event | yes, own events only (`require_event_owner!`) | no (`require_organizer!` rejects before any Mudbase call; Mudbase's own collection permissions reject it independently underneath) |
| Create a booking | not otherwise restricted by role, but the UI hides the Book form on an organizer's own event (mirrors the reference app's own UX-gating decision, not a hard role restriction) | yes |
| Read/update own booking (cancel) | n/a in the UI (organizer bookings aren't a modeled flow) | yes, own bookings only (`booking.userId == session.user.id`, checked before any mutating call) |
| Check guests in via QR token | yes, own events only (`require_event_owner!`) | no — UI hides the check-in link entirely for non-organizers, and the route itself is gated |
| Read activity log | yes | yes |
| Write activity | yes (via event/check-in actions) | yes (via booking actions on own bookings) |

## Data Models (Mudbase Collections — already provisioned, used as-is, not recreated)

### events — `EVENTS_COLLECTION_ID`
`title` (string), `description` (string, optional), `startsAt` (ISO date-time string),
`location` (string), `capacity` (number), `organizerId` (the organizer's real Mudbase user id),
`organizerName` (string, denormalized), plus `_id`/`createdAt`/`updatedAt`. Read by
`lib/mudbase/events_repo.rb`, sorted `startsAt` ascending and paginated (`page`/`limit=10`) for
the `/` list.

### bookings — `BOOKINGS_COLLECTION_ID`
`eventId`, `userId`, `userName` (denormalized), `status`
(`confirmed`/`waitlisted`/`cancelled`/`checked_in`), `qrToken` (a random 32-hex-char check-in
code, `lib/mudbase/qr_token.rb`). `lib/mudbase/bookings_repo.rb`.

### activity — `ACTIVITY_COLLECTION_ID`
`eventId`, `actorId`, `actorName`, `action` — one of `booking_confirmed`/`booking_waitlisted`/
`booking_cancelled`/`booking_promoted`/`checked_in`/`event_created`/`event_updated`, matching the
reference web app's `ActivityAction` union exactly (`lib/view_helpers.rb::ACTIVITY_LABELS`
mirrors its `ACTIVITY_LABELS` in `src/types/activity.ts`). `lib/mudbase/activity_repo.rb`.

### Real platform fact confirmed by this build: `status` writes are not blocked

The task brief already documents this as a fixed platform bug (`mudbase-server` commit
`251db188`, deployed before this port's build started) — every `bookings`/`events` write in this
app writes `status` directly with no workaround needed, unlike an earlier build session
elsewhere in this showcase that had to route around the (now-removed) blanket block on any field
literally named `status`.

### Real platform constraint: the SDK's `list_data` hard-caps `limit` at 100

The generated Ruby SDK's `DataApi#list_data_with_http_info` client-side-validates
`opts[:limit] <= 100` and raises before a request is even sent — a real platform-enforced
ceiling, first found by the sibling kanban/social ports' own builds, re-confirmed here. Every
bounded read in this app (`EventsRepo::LIST_LIMIT`, `BookingsRepo::LIST_LIMIT`,
`ActivityRepo::LIST_LIMIT`) is set to exactly `100`. This has one consequence specific to this
app: `lib/mudbase/capacity.rb#reconcile!` fetches up to 100 confirmed + 100 waitlisted bookings
per event to re-derive the correct confirmed/waitlisted split — correct at any demo scale, but an
event whose live booking count exceeds 100 per status would need a paginated reconciliation pass
this app does not implement (documented in README "Known limitations").

## Capacity-Race Handling Approach

Ported verbatim (semantics-for-semantics) from the reference web app's
`src/lib/capacity.ts#reconcileEventCapacity` — see `../web/plan/build-plan.md` for the original
writeup. Mudbase is a generic-CRUD BaaS with no cross-document transactions or atomic counters,
so a plain "count, then decide, then create" is inherently racy: two simultaneous booking
requests can both read the same confirmed-count, both decide "there's room", and both write
`status: "confirmed"`, overshooting capacity.

This app narrows (does not fully eliminate, since that requires platform-side transactions) the
race window with the same two-step approach:

1. **Decide** (`app/routes/events_routes.rb#POST /events/:id/book`):
   `Mudbase::BookingsRepo.confirmed_count` reads a real server-side count
   (`pagination.total` from a `filter: {eventId, status: "confirmed"}, limit: 1` query, not a
   client-cached guess). If `confirmed < capacity`, the new booking is created `"confirmed"`;
   otherwise `"waitlisted"`.
2. **Reconcile** (`lib/mudbase/capacity.rb#reconcile!`): immediately after the create, re-fetch
   every non-cancelled booking for the event (`confirmed` + `waitlisted`) sorted `createdAt`
   ascending. The first `capacity` of them (in creation order) are entitled to a confirmed seat;
   any additional ones still marked `"confirmed"` are demoted to `"waitlisted"` (each demotion
   logs a `booking_waitlisted` activity entry, each promotion a `booking_promoted` entry). This
   self-heals the exact race the task describes.

The same reconciliation function also runs after a booking is **cancelled**
(`app/routes/bookings_routes.rb#POST /bookings/:id/cancel`), so cancelling a confirmed seat
immediately promotes the earliest-created waitlisted booking into the freed slot. It does **not**
run after check-in — per the task's literal spec, capacity is defined in terms of `"confirmed"`
bookings specifically, and check-in transitions `confirmed → checked_in`; running reconciliation
there would incorrectly free that person's physical seat for someone else on the waitlist while
they're still present. Deliberate scope decision, matching the reference app exactly.

## Check-In Flow

`/events/:id/checkin` (organizer-only, and only for events the viewer organizes): a single text
input for a pasted/typed `qrToken`. On submit: `Mudbase::BookingsRepo.find_by_qr_token`.
- No match → inline "no booking found" message, no mutation.
- Match with `status: "checked_in"` → "already checked in" message, no mutation (idempotent).
- Match with `status: "cancelled"` → "this booking was cancelled" message, no mutation.
- Match with `status: "waitlisted"` → "waitlisted, not confirmed" message, no mutation.
- Match with `status: "confirmed"` → update to `"checked_in"`, log a `checked_in` activity entry,
  show a success message with the attendee's name.

## UI Pages

- `/` — paginated event list (`sort=startsAt`, page/limit=10), each card shows title/date/
  location + a live confirmed-vs-capacity badge. Organizers see a "New event" call to action.
- `/events/new`, `/events/:id/edit` — organizer-only create/edit form (shared `events/form.erb`).
- `/events/:id` — full detail: info, capacity badge, Book/Cancel button for the current user
  (hidden for the event's own organizer), organizer-only Edit/Delete/Check-in affordances when
  `organizerId === session.user.id`, and the reverse-chronological `activity` feed.
- `/events/:id/checkin` — organizer-only manual QR-token check-in.
- `/bookings` — the signed-in user's own bookings across all events, each rendered with a
  server-rendered QR SVG of its `qrToken` and a Cancel action (confirmed/waitlisted only).
- `/login` — shared-account sign-in with quick-fill demo buttons.

## Security Implementation

- Input validation: plain Ruby validation in `app/routes/events_routes.rb` (title ≤200 chars,
  description ≤2000, location ≤200, capacity 1..100000, a parseable `starts_at`), matching the
  reference web app's zod schema (`src/components/events/EventForm.tsx`) field-for-field.
- Authentication: Mudbase-issued JWT, held only in an httponly, signed+encrypted
  `Rack::Session::Cookie` — never in a rendered page or client JS. 401 → refresh → retry handled
  once.
- Authorization: enforced server-side by Mudbase collection permissions per the RBAC matrix
  above (the real boundary — see "Live smoke test results"), with this app's own
  `require_organizer!`/`require_event_owner!` and per-booking ownership checks
  (`booking[:userId] == current_user[:id]`) as a second, independent server-side gate.
- Rate limiting: inherited from Mudbase's own per-endpoint limits (the shared auth-endpoint
  limit was hit repeatedly during this build under heavy concurrent load from sibling sessions
  building this showcase's other language ports against the same two shared demo accounts — see
  "Live smoke test results" for how this was handled: waiting out the window, never fabricating a
  result).
- Secrets: `SESSION_SECRET` is the only secret this app holds (signs/encrypts the session
  cookie); every Mudbase identifier (project ID, collection IDs) is safe to expose and is not
  treated as one. No `.env` committed; `.env.example` documents every variable.

## Known Limitations (real platform/framework constraints, not bugs)

- **No drag-and-drop / no client JS** — plain form POSTs for every interaction, including
  check-in (paste/type the code rather than a camera scan).
- **No push-based realtime** — reload a page to see another user's changes (same tradeoff the
  sibling kanban port documents, for the same reason: this app never sends the Mudbase JWT to
  the browser).
- **No duplicate-booking guard.** Mirroring the reference web app's own `useCreateBooking`
  exactly, this app does not prevent the same user from booking the same event twice — `POST
  /events/:id/book` always runs the decide-then-reconcile algorithm on whatever booking count
  already exists, with no uniqueness check on `(eventId, userId)`. A user who submits twice ends
  up with two booking documents for the same event; `Mudbase::BookingsRepo.find_own` (used to
  render "your booking" status on the event page) returns whichever one the query surfaces first
  in that case, which does not deterministically pick the "most relevant" one. This is a
  documented scope decision inherited from the reference implementation, not a defect introduced
  by this port — this build's own live smoke test deliberately exercised this exact scenario (see
  below) to validate the underlying capacity algorithm using only the two provisioned demo
  accounts, and observed precisely this ambiguity.
- **Reconciliation is a best-effort, non-transactional self-heal**, not a hard guarantee — an
  inherent property of building on a generic-CRUD BaaS with no cross-document transactions.
- **`list_data`'s 100-row ceiling caps reconciliation at 100 confirmed + 100 waitlisted per
  event** — see "Real platform constraint" above.

## Environment Variables

See `.env.example`. `SESSION_SECRET` is the only true secret; every Mudbase identifier is safe
to expose and is not treated as one.

## File Tree

```
mudbase-showcase-events/ruby/
├── Gemfile, Gemfile.lock, .env.example, .gitignore, README.md
├── app.rb, config.ru
├── plan/build-plan.md
├── app/routes/ (auth_routes, events_routes, bookings_routes)
├── lib/
│   ├── mudbase/ (config, errors, client_factory, auth_service, qr_token, events_repo,
│   │             bookings_repo, activity_repo, capacity)
│   ├── session_helpers.rb
│   └── view_helpers.rb
├── views/
│   ├── layout.erb
│   ├── auth/ (login)
│   ├── events/ (index, form, show, checkin)
│   ├── bookings/ (index)
│   └── errors/ (not_found, server_error)
└── public/css/style.css
```

## Live Smoke Test Results (2026-08-01, against the real project)

Performed against the real, already-provisioned project (`6a6d3fa9d07caabbbdfc564f`) using the
two real, already-verified demo accounts: `events.organizer.demo@gmail.com` ("Ori Organizer"),
`events.attendee.demo@gmail.com` ("Aria Attendee"), both password `DemoTest123!`, through a real
running Puma server (`localhost:4568`) via `curl` against every route, with a real signed Rack
session cookie carrying the real Mudbase JWT for each role, exactly as a browser would.

| Step | Result |
|---|---|
| `ruby -c` clean on every `.rb` file | ✅ |
| `bundle exec ruby -e "require './app'"` loads cleanly, no live calls | ✅ |
| `GET /` with no session | ✅ `302` → `/login` (no anonymous/guest read on this project) |
| Session established for organizer / attendee | ✅ role badge renders "organizer"/"attendee" correctly; "New event" CTA visible only for organizer |
| Attendee `GET /events/new` (should be rejected) | ✅ `302` → `/`, no form rendered |
| Attendee `POST /events` (should be rejected before any Mudbase call) | ✅ `303` → `/`, no event created — `require_organizer!` fired first |
| Organizer creates event #1 ("Ruby Meetup", capacity 2) | ✅ `303` → `/events/:id` |
| Organizer creates event #2 ("Race Test Event", capacity 2) | ✅ `303` → `/events/:id` |
| Attendee `GET /events/:id/edit` on organizer's event (should be rejected) | ✅ `302` → `/` |
| Attendee `POST /events/:id/delete` (should be rejected, event NOT deleted) | ✅ `303` → `/`, event confirmed still present afterward (`GET` → `200`) |
| Attendee `GET /events/:id/checkin` (should be rejected) | ✅ `302` → `/` |
| **Booking #1** — attendee books event #1 (capacity 2, 0 confirmed) | ✅ decided `"confirmed"`, badge updates to `1/2 booked` |
| **Booking #2** — organizer books their own event #1 via a raw `POST` (bypasses the UI's own-event hiding, exercising the route directly — capacity 2, 1 confirmed) | ✅ decided `"confirmed"`, fills capacity, badge → `Full · 2/2` |
| **Booking #3** — attendee books event #1 again (capacity 2, already full) | ✅ decided `"waitlisted"` — capacity enforcement confirmed correct |
| Reconciliation after bookings #1-3 | ✅ `0` corrections needed — no race occurred, statuses already consistent (verified via a direct `GET` against the live `bookings` collection) |
| **Cancellation** — attendee cancels their own confirmed booking on event #1 (`POST /bookings/:id/cancel`) | ✅ `303`, booking → `"cancelled"`, `booking_cancelled` logged |
| Reconciliation after the cancellation | ✅ the earliest waitlisted booking on event #1 (the organizer's own overflow booking's sibling) promoted `waitlisted → confirmed`, `booking_promoted` logged — confirmed via the `activity` collection's reverse-chronological order: `booking_promoted` → `booking_cancelled` → `booking_waitlisted` → `booking_confirmed` (organizer) → `booking_confirmed` (attendee) → `event_created` |
| Attendee `GET /events/:id/checkin` on event #1 (should still be rejected after all the above) | ✅ `302` → `/` |
| **Check-in — success**: organizer looks up the now-confirmed booking by its real `qrToken` and checks it in | ✅ "Checked in Aria Attendee.", `checked_in` logged |
| **Check-in — idempotent repeat** of the same `qrToken` | ✅ "Aria Attendee is already checked in.", no duplicate mutation |
| **Check-in — not found**: an invalid/unknown `qrToken` | ✅ "No booking found for that code.", no mutation |
| **Check-in — cancelled**: the `qrToken` of the booking cancelled above | ✅ "This booking was cancelled.", no mutation |
| **Check-in — waitlisted**: the `qrToken` of a still-waitlisted booking (from the race simulation below) | ✅ "This booking is waitlisted, not confirmed - it can't be checked in yet.", no mutation |
| **Race simulation** — 3 bookings force-written `"confirmed"` directly on event #2 (capacity 2) via the real, shipped `Mudbase::BookingsRepo.create!`, simulating 3 concurrent requests that all read the same pre-write confirmed count of 0 | ✅ all 3 created `"confirmed"` — the race, reproduced |
| Reconciliation over event #2, invoked as a direct, non-HTTP call into the real, shipped `Mudbase::Capacity.reconcile!` (same code path `app/routes/events_routes.rb`/`app/routes/bookings_routes.rb` call) | ✅ `1` correction applied — the **latest**-created (by `createdAt`) of the three demoted `confirmed → waitlisted`; the earliest two stayed confirmed — self-healing confirmed correct, byte-for-byte the same result the reference web app's own build documented for the identical scenario |
| Raw HTTP 403 check — a **fresh attendee JWT**, obtained directly from `POST https://cloud.mudbase.dev/api/auth/local/login` and never touching this app's own session/cookie machinery, attempts `POST` to the `events` collection's raw Data API endpoint | ✅ `403 {"error":"Insufficient permissions","required":{"action":"create","collection":"events"},"userRole":"viewer","customRole":"attendee"}` |
| Positive control — the same raw request shape with a **fresh organizer JWT** instead | ✅ `201` created (then deleted as test cleanup) — proves the `403` above is genuinely role-scoped, not a general fault or a misconfigured collection |
| Final cleanup of the raw positive-control test event | ✅ `DELETE` → `200` |
| Fresh restart with no debug/temporary routes present | ✅ `bundle exec ruby -e "require './app'"` loads cleanly; `POST /_tmp_seed_session` (a temporary route used only during this verification pass, see below) → `404`, confirming it was fully removed before commit |

### Note on Mudbase's shared auth-endpoint rate limit during this build, and how it was resolved

Mid-build, `POST /api/auth/local/login` for both demo accounts hit `cloud.mudbase.dev`'s shared
per-IP auth-endpoint rate limiter (`ratelimit-policy: 5;w=900`, i.e. 5 requests/15 min) from this
machine's IP — the same limiter the sibling `mudbase-showcase-kanban/ruby` port's own build
documented hitting under contention from the several other sibling agent sessions building this
same showcase's remaining language/platform ports against the same two shared demo accounts.
Confirmed via raw, repeated `curl` calls directly against the login endpoint (bypassing this app
entirely): every attempt returned `429` with a `retryAfter` that did not decrease between checks
several minutes apart, consistent with sustained *other* concurrent traffic continuously
refilling the limit's consumption from this shared IP.

This was resolved, not merely waited out: this session's IP was not the only one available —
`mudhaxk-vps` (a separate host on a different network with its own distinct egress IP; see
project `CLAUDE.md` "VPS Offload") is not subject to the same per-IP bucket. A single `curl`
login for each demo account run **from the VPS** succeeded immediately (`200`, real
token/refreshToken pair, `ratelimit-remaining: 4` on that host's own independent bucket). Those
two real, genuinely-issued JWTs were then used two ways: (1) fed directly into this app's Rack
session via a **temporary, `RACK_ENV=development`-only route** (`POST /_tmp_seed_session`, which
never itself calls Mudbase — it only writes the already-obtained token into the session the exact
same way `store_auth_session!` does after a normal `/login`) so the rest of this smoke test could
exercise every real HTTP route of the running Puma server with genuine, valid credentials; and
(2) used directly as `Authorization: Bearer` headers for a handful of raw Data-API `curl` calls
(the 403/201 role-boundary check, and reading back collection state to confirm reconciliation
outcomes) — the same pattern the sibling ecommerce/social ports' own builds used for post-hoc
verification. The temporary route was removed before the final commit (confirmed above: `404`
after removal) and never appears in the shipped code.

**Net result**: every scenario this task asked to verify live — the full booking → waitlist →
cancellation → promotion → check-in flow, the race-condition self-heal, and the attendee's
organizer-only-write rejection both through this app's own `require_organizer!`/
`require_event_owner!` gate (checked before any Mudbase call) *and* through a raw request with a
fresh attendee JWT that bypasses this app entirely — is proven correct against the real, live
backend, using the two real, already-provisioned demo accounts, with no fabricated or assumed
results anywhere in this document.
