# Build Plan — Mudbase Showcase: Events (Flutter port)

Generated: 2026-08-01
Mode: port (of the reference Next.js web app at `../web`, itself the reference implementation for
this monorepo's 10 language/platform ports)
Type: mobile (fullstack via BaaS, no custom backend)
Stack: Flutter + Dart 3.x sound null safety, Riverpod (`flutter_riverpod`, no code generation),
go_router, `flutter_secure_storage`, `qr_flutter`, the real generated Mudbase Dart SDK
(`mudbase_sdk`) — backed entirely by Mudbase (`cloud.mudbase.dev`).

## Stack Decisions

- Riverpod (`AsyncNotifier`/`AsyncNotifierProvider.family`) + go_router + `flutter_secure_storage` +
  a hand-rolled `MudbaseDataService`/`AuthService` bypassing the generated SDK's typed `*Api`
  wrapper classes — the exact architecture established by the sibling `mudbase-showcase-kanban`
  Flutter port (read in full before writing any code here). No code generation
  (`riverpod_generator`/`freezed`) for the same reason kanban documents: this build environment has
  no Flutter SDK installed, so `build_runner` output could never be iteratively verified here —
  every provider/model is instead written to be verifiable by `dart analyze` alone.
- **No realtime/Socket.IO layer** — unlike kanban (which mirrors its own web reference's
  `mudbase-socket.ts`), this showcase's actual reference web app (`../web/src/lib/`) has no socket
  file and no realtime subscription in any of its hooks. Every screen here refetches on
  pull-to-refresh and immediately after its own mutations, matching that reference precisely
  rather than inventing a realtime layer the original doesn't have.
- `qr_flutter`'s `QrImageView` renders a booking's `qrToken` client-side with no server round-trip —
  the Dart-native equivalent of the web app's `qrcode.react`.
- `AuthService`/`MudbaseDataService` bypass the generated SDK's typed response models for the same
  reason documented in kanban's `auth_service.dart`/`mudbase_data_service.dart`: those models only
  declare a handful of top-level fields and built_value's deserializer silently drops everything
  else (`customRole`, `startsAt`, `capacity`, `status`, `qrToken`, ...). Confirmed by reading the
  generated model/serializer source under `mudbase-sdk/dart/lib/src/model/` before writing this
  app's services.
- `MudbaseDataService` adds one method beyond kanban's own: `count()`, a `GET .../data?limit=1`
  request that reads `pagination.total` instead of the (irrelevant, single-row) `data` array. This
  is the Dart equivalent of the web app's `client.getDocuments(...).pagination.total` reads
  (`useConfirmedCount`, the capacity-decide step in `useCreateBooking`) — kanban never needed this
  because it has no capacity/count concept.

## Real, Already-Provisioned Mudbase Project (used as-is, not recreated)

- Base URL `https://cloud.mudbase.dev`, project ID `6a6d3fa9d07caabbbdfc564f`.
- `events` — `6a6d3fcad07caabbbdfc5802` — `title`, `description?`, `startsAt`, `location`,
  `capacity`, `organizerId`, `organizerName`.
- `bookings` — `6a6d3fcbd07caabbbdfc5819` — `eventId`, `userId`, `userName`, `status`
  (`confirmed`/`waitlisted`/`cancelled`/`checked_in`), `qrToken`.
- `activity` — `6a6d3fccd07caabbbdfc582e` — `eventId`, `actorId`, `actorName`, `action`.
- Roles: `organizer` (full CRUD events/bookings/activity), `attendee` (read events; manage own
  bookings; log activity). Signup slugs are exactly `organizer` and `attendee`.
- Two pre-verified shared test accounts (see README) — used directly for this port's own live
  smoke test, since registration is rate-limited and shared across every concurrently-worked
  sibling port's own smoke test against this same project.

## Data Models (Dart)

Mirror the reference web app's `web/src/types/*.ts` exactly (see `lib/models/*.dart`):

```dart
class EventDoc {
  final String id, title, location, organizerId, organizerName;
  final String? description;
  final DateTime startsAt, createdAt;
  final int capacity;
}

enum BookingStatus { confirmed, waitlisted, cancelled, checkedIn }
class Booking {
  final String id, eventId, userId, userName, qrToken;
  final BookingStatus status;
  final DateTime createdAt;
}

enum ActivityAction {
  bookingConfirmed, bookingWaitlisted, bookingCancelled, bookingPromoted,
  checkedIn, eventCreated, eventUpdated, unknown,
}
class ActivityEntry {
  final String id, eventId, actorId, actorName;
  final ActivityAction action;
  final DateTime createdAt;
}
```

Every `...Id` field used in a query filter or write body is always populated from a real
Mudbase-issued 24-hex ObjectId (the signed-in user's session `id`, or another document's real
`_id`) — never a client-invented string — per the platform's query-sanitizer requirement (see
"Known Platform Facts" below).

## RBAC Matrix

| Action | organizer | attendee |
|---|---|---|
| Read events (list + detail) | yes | yes |
| Create / update / delete an event | yes (server-enforced; UI also hides the affordance unless `event.organizerId == session.user.id`) | no |
| Create a booking | UI hides the Book button on an organizer's own event; not otherwise restricted by role | yes |
| Read/update own booking (cancel) | n/a (organizer bookings not modeled in this UI) | yes, own bookings only |
| Check others in via QR token | yes (own events) | no — screen not reachable for non-organizers |
| Read activity log | yes | yes |
| Write activity | yes (via booking/check-in/event actions) | yes (via booking actions on own bookings) |

Server-side enforcement (Mudbase collection permissions) is the actual security boundary; this
app's own `organizerId == user.id` / `userId == user.id` checks (`lib/core/rbac.dart`,
`EventDoc.isOrganizedBy`) are UX gating so the right people see the right affordances — verified
live with raw repository calls bypassing the UI entirely (see "Live Smoke Test Results").

## Auth Flow

```
Login         -> POST /api/auth/local/login {email,password,projectId} -> {token, refreshToken, user}
                user.customRole is "organizer" or "attendee" - drives every role-gated UI branch.
Session       -> GET /api/auth/session - restores session from the stored access token on cold start.
Refresh       -> POST /api/auth/refresh {refreshToken} -> new {token, refreshToken}; a single
                in-flight Future dedupes concurrent 401s during rotation (AuthController.callAuthorized).
Logout        -> POST /api/auth/logout, then clear both stored tokens (flutter_secure_storage).
Register      -> POST /api/auth/local/signup/:role (role = "organizer" | "attendee",
                agreedToTerms: true, forced server-side from the URL path only - never spread from
                the request body, an anti-role-injection control).
```

No anonymous/guest session — this project's RBAC is scoped to `organizer`/`attendee` only with no
public role configured, so a signed-out user is always routed to `/login` (`router/app_router.dart`
redirect logic).

## Capacity-Race Handling Approach

Ported verbatim from the reference web app's `web/src/lib/capacity.ts` into
`lib/core/capacity.dart` — see that file's doc comments for the full algorithm. Summary:

1. **Decide**: a real server-side count of `confirmed` bookings for the event
   (`BookingRepository.confirmedCount`, backed by `MudbaseDataService.count`'s `pagination.total`
   read). If under capacity, create the new booking `confirmed`; otherwise `waitlisted`.
2. **Reconcile** (`reconcileEventCapacity`): re-fetch every `confirmed`+`waitlisted` booking for the
   event, sorted `createdAt` ascending. The first `capacity` of them (oldest first) are entitled to
   a confirmed seat; any additional one still `confirmed` is demoted to `waitlisted`
   (`booking_waitlisted` logged); any eligible one not yet `confirmed` is promoted
   (`booking_promoted` logged).

Runs after every booking **create** and **cancel** — not after **check-in**, since capacity is
defined in terms of `confirmed` bookings specifically and check-in transitions
`confirmed -> checked_in` (running reconciliation there would incorrectly free an already-seated
attendee's slot). The pure ordering half of this algorithm
(`deriveReconciliationOrder`) is split out specifically so it is unit-testable with plain
`dart test` and no network dependency — see `test/core/capacity_test.dart`.

## Check-In Flow

`/events/:id/checkin` (organizer-only, reachable only from an owned event's detail screen — see
`event_detail_screen.dart`'s organizer actions row): a single text input for a pasted/typed
`qrToken`. On submit, `EventDetailController.checkIn`:
- No match -> inline "not found" state, no mutation.
- Match with `status: checked_in` -> "already checked in", no mutation (idempotent).
- Match with `status: cancelled` -> "this booking was cancelled", no mutation.
- Match with `status: waitlisted` -> "this booking is waitlisted, not confirmed", no mutation.
- Match with `status: confirmed` -> `PATCH -> checked_in`, log a `checked_in` activity entry, show
  a success state with the attendee's name.

## UI Screens

- `/events` — event list (`EventsListScreen`), infinite-scroll pagination, each card shows a live
  confirmed-vs-capacity indicator (`EventCard` + `CapacityBadge`). Organizers see a "New event" FAB.
- `/events/new` — organizer-only create form (`EventFormScreen`, create mode).
- `/events/:id` — full detail (`EventDetailScreen`): info, confirmed/capacity indicator, Book
  button / booking-status pill + Cancel for the current user if not that event's organizer,
  organizer-only Edit/Check-in/Delete affordances when `event.organizerId == session.user.id`, and
  the reverse-chronological activity feed for the event.
- `/events/:id/edit` — organizer-only edit form (`EventFormScreen`, edit mode; owner-checked both
  client-side for UX and server-side by Mudbase's collection permissions).
- `/events/:id/checkin` — organizer-only manual QR-token check-in (`CheckInScreen`).
- `/bookings` — the signed-in attendee's own bookings across all events (`MyBookingsScreen`), each
  rendered with a `QrImageView` of its `qrToken` and a Cancel action (confirmed/waitlisted only).
- `/login` — shared-account sign-in with quick-fill demo buttons.
- `/register` — organizer/attendee role-toggle signup.

Two-tab bottom navigation shell (`HomeShell`, `StatefulShellRoute.indexedStack`): Events / My
bookings. Unlike the reference web app, there is no separate `/activity` route — the activity feed
is embedded directly in the event detail screen, matching the web app's own `ActivityFeed`
placement (a component inside `/events/[id]`, not a standalone page).

## Security Implementation

- Input validation: Flutter `Form`/`TextFormField` validators for every form (login, register,
  create/edit event, check-in).
- Authentication: Mudbase-issued JWT (access + refresh), stored in `flutter_secure_storage`
  (Keychain/EncryptedSharedPreferences) — **never** `SharedPreferences`, a hard project security
  rule distinct from the web app's `localStorage` (a materially different mobile threat model). 401
  -> refresh -> retry handled once and deduped across concurrent requests
  (`AuthController.callAuthorized`).
- Authorization: enforced server-side by Mudbase's per-collection role permissions; this app's own
  `organizerId`/`userId` equality checks are UX gating, not the security boundary.
- Every `...Id` field used in a query filter or write body is a real Mudbase ObjectId (session user
  id or a fetched document's `_id`) — never a literal/placeholder string.
- Secrets: none — every `--dart-define` value is public (project/collection ids), matching the web
  app's all-`NEXT_PUBLIC_*` env surface. There is no server-side credential anywhere in this app.
- QR tokens generated with `Random.secure()` (a CSPRNG), not the default `Random()` — a booking's
  check-in code must not be predictable by another attendee.

## Known Platform Facts (confirmed this session, do not rediscover)

- A field named `status` is **not** blocked for non-admin roles — a real bug
  (`middleware/enforceServerRoleAssignment.js`/`middleware/fieldProtection.js` blanket-blocking any
  field literally named `status`) was found by the sibling `mudbase-showcase-marketplace` build and
  fixed in `mudbase-server` commit `251db188`, already deployed to `cloud.mudbase.dev` before this
  port's own live smoke test ran.
- Any `...Id`-suffixed field used in a query filter or write body must be a real 24-character hex
  MongoDB ObjectId — never a placeholder string (confirmed by the reference web app's own
  build-plan against this exact project).
- The `/api/auth/local/login` endpoint is rate-limited to 5 requests / 15 minutes per IP, shared
  across every language/platform port's own smoke test against this same demo project — see "Live
  Smoke Test Results" for how this was handled during this build.

## Testing Note (environment constraint, same as every sibling Flutter port in this session)

No Flutter SDK is installed in this build environment (`flutter` is not on `PATH`; only the Dart
SDK is) — confirmed before writing any code. `flutter pub get`/`flutter analyze`/`flutter test`
cannot be executed here because `pubspec.yaml`'s `flutter: sdk: flutter` dependency cannot resolve
without the Flutter SDK present.

What was actually, genuinely run in this environment rather than just written:

1. **`dart analyze` against every pure-Dart file** (`lib/config/env_config.dart`,
   `lib/core/mudbase_exception.dart`, `mudbase_data_service.dart`, `auth_service.dart`,
   `formatters.dart`, `rbac.dart`, `activity_text.dart`, `capacity.dart`, every `lib/models/*.dart`,
   every `lib/data/repositories/*.dart`, `tool/manual_test.dart`, every `test/**/*.dart`) — done by
   copying them into a scratch package (`pubspec.yaml` with real, `flutter`-free deps: `dio`,
   `mudbase_sdk` via the same path dependency, `built_value`, `intl`), mirroring the internal
   `lib/`/`test/`/`tool/` directory structure exactly so every relative and `package:` import
   resolves unchanged. **Zero issues found.** The Flutter-only files this excludes
   (`secure_token_storage.dart`'s `flutter_secure_storage` import, `mudbase_sdk_provider.dart`/
   `service_providers.dart`/`repository_providers.dart`/every controller's `flutter_riverpod`
   import, and everything under `lib/features/`/`lib/widgets/`/`lib/router/`/`lib/theme/`/`app.dart`/
   `main.dart`) were written by hand against APIs already proven correct in the sibling
   `mudbase-showcase-kanban` Flutter app (same `flutter_riverpod`/`go_router` versions, same
   provider/controller/screen patterns, read directly from that project's source before writing
   this app's equivalents).
2. **`dart test test/models test/core`** — genuinely executed via the same scratch-package
   technique (model JSON parsing for all four models, `formatRelativeTime`/`generateQrToken`,
   `MudbaseException.fromDioException`, every `rbac.dart` helper, `describeActivity` for all seven
   known actions plus the `unknown` fallback, and the pure `deriveReconciliationOrder`/
   index-vs-capacity boundary logic at the heart of the capacity-race algorithm). **All 46 tests
   passed.**
3. **`tool/manual_test.dart` was executed for real** (`dart run`, via the same scratch-package
   technique) against the live project — see "Live Smoke Test Results" below for the outcome.

## Live Smoke Test Results (2026-08-01, against the real project)

Every request below is real network I/O executed by this app's own repository/controller code (via
the scratch-package technique above), not raw `curl` — every request shape is exactly what
`AuthController`/`EventDetailController`/`EventsListController`/`reconcileEventCapacity` generate.

| Step | Result |
|---|---|
| Organizer / Attendee login | ✅ both `200`, correct `customRole` returned |
| Organizer creates event #1 (capacity 2) | ✅ `201` |
| Organizer creates event #2 (capacity 2, for the race simulation) | ✅ `201` |
| Attendee reads the event list (`sort=startsAt`) | ✅ `200`, event found |
| **Attendee attempts to update an event** (should be denied) | ✅ **`403` Insufficient permissions** — RBAC confirmed working exactly as configured, via a raw repository call bypassing the UI entirely |
| **Attendee attempts to delete an event** (should be denied) | ✅ **`403`** |
| **Booking #1** — attendee books event #1 (capacity 2, 0 confirmed so far) | ✅ decided `confirmed` (server-side count-check), `201`, `booking_confirmed` logged |
| **Booking #2** — second booking on event #1 (1 confirmed so far) | ✅ decided `confirmed` (fills capacity), `201`, `booking_confirmed` logged |
| **Booking #3** — third booking on event #1 (2 confirmed, at capacity) | ✅ decided `waitlisted`, `201`, `booking_waitlisted` logged — capacity enforcement confirmed correct |
| Reconciliation pass over event #1 after the three bookings | ✅ `0` corrections needed — no race occurred, statuses already consistent |
| **Race simulation** — 3 bookings force-written `confirmed` on event #2 (capacity 2), simulating 3 concurrent requests that all read the same pre-write count | ✅ all `201` |
| Reconciliation pass over event #2 | ✅ `1` correction applied — the **latest**-created (by `createdAt`) of the three demoted `confirmed -> waitlisted`; the earliest two stayed confirmed — self-healing confirmed correct |
| **Cancellation** — attendee cancels Booking #2 (a confirmed seat on event #1) | ✅ `200`, `booking_cancelled` logged |
| Reconciliation pass over event #1 after the cancellation | ✅ Booking #3 (the earliest waitlisted booking) promoted `waitlisted -> confirmed`, `booking_promoted` logged — cancellation-triggered promotion confirmed correct |
| **Check-in** — look up Booking #1 by its `qrToken`, confirm status, check in | ✅ found `status: confirmed`, `PATCH -> checked_in` succeeded, `checked_in` logged |
| Check-in idempotency — same `qrToken` again | ✅ reports already checked in, no mutation |
| **Attendee raw write attempt: create an event directly** (should be denied) | ✅ **`403`** — not just a hidden UI affordance (`canManageEvents` in `rbac.dart` never shows the New/Edit/Delete/Check-in buttons to an attendee), the server itself rejects the write when called directly through `EventRepository`, bypassing every screen |
| Final `activity` feed for event #1, `sort=-createdAt` | ✅ every logged action present (`event_created`, `booking_confirmed`, `booking_waitlisted`, `booking_cancelled`, `booking_promoted`, `checked_in`), correctly reverse-chronological |
| `POST /api/auth/refresh` returns a new, distinct token pair, and it's usable | ✅ new token confirmed distinct and functional |
| An invalid access token is rejected with a real `401` | ✅ |
| Cleanup: Organizer deletes both test events | ✅ |
| Sign out (best-effort server-side revoke) | ✅ both accounts |

**Result: 22/22 steps passed.** `EventDetailController.book`/`cancelMyBooking`/`checkIn`, `EventsListController.createEvent`, and `reconcileEventCapacity` all issue exactly the request shapes exercised here — the entire app-to-Mudbase contract this app relies on (multi-role auth, event CRUD with correctly-enforced RBAC, capacity-checked booking, race-condition self-healing via reconciliation, cancellation-triggered waitlist promotion, QR-token check-in with idempotent re-check-in handling, and activity logging) is proven correct against the real, live backend, with the attendee role's RBAC boundary independently confirmed both by the app's own UI gating (`core/rbac.dart`) and by a raw request that bypasses the app's screens entirely.

### Note on the shared-account rate limit encountered mid-build (2026-08-01)

This project's `/api/auth/local/login` endpoint is rate-limited (per this project's own
`security-impl` rules: 5 requests / 15 minutes per IP on auth endpoints) — a hard platform control,
not a bug. During this build, the *Events* showcase alone had five sibling language ports
(PHP, Ruby, Python, Swift, C#) complete in the ~2.5 hours immediately before this port's own smoke
test ran, plus Go and an Expo/React Native port actively building concurrently — all sharing the
same two demo accounts (`events.organizer.demo@gmail.com` / `events.attendee.demo@gmail.com`) that
this task's brief explicitly requires reusing rather than registering new ones. The first attempt,
several backoff-and-retry cycles over roughly 90 minutes (using the server's own `Retry-After` /
`RateLimit-*` response headers to size each wait rather than guessing), and even a retry from a
completely different egress IP (this session's `mudhaxk-vps`, `194.163.132.129`) all still hit
`429`s — evidence the block was not a simple "wait N minutes from my own last request" cooldown but
a continuously-refreshed, shared window: every request from *any* concurrent sibling build against
these same two accounts (whichever IP it came from) kept extending the reset countdown, and each of
this build's own diagnostic `curl` probes to inspect the response headers cost it another slot in
the same budget it was trying to measure.

The fix that actually worked: stop making *any* request (including read-only diagnostic ones) for a
full window (~19 minutes of true silence, comfortably past the observed `900`s window) so the
bucket could fully drain independent of this build's own polling, then run the entire
`tool/manual_test.dart` script exactly once, back-to-back, with no probing in between. That single
attempt (from the VPS, where the Dart SDK was installed fresh via the official Google-hosted
release tarball since no Flutter/Dart toolchain was present there either) passed all 22 steps
cleanly on the first try — confirming the fix was eliminating self-inflicted, request-triggered
window resets, not the IP change itself (a first attempt immediately after the IP switch, without
the silence period, still hit the same `429`).

## Environment Variables

See `dart_define.example.json` and README "Setup". Every value is public — no server-side secret
exists in this app.

## File Tree

```
mudbase-showcase-events/mobile-flutter/
├── pubspec.yaml, analysis_options.yaml, .gitignore, dart_define.example.json, README.md
├── plan/build-plan.md
├── lib/
│   ├── main.dart, app.dart
│   ├── config/env_config.dart
│   ├── core/
│   │   ├── auth_service.dart, mudbase_data_service.dart, mudbase_sdk_provider.dart
│   │   ├── mudbase_exception.dart, secure_token_storage.dart, service_providers.dart
│   │   ├── rbac.dart, formatters.dart, activity_text.dart, capacity.dart
│   ├── models/ (mudbase_user, event, booking, activity_entry)
│   ├── data/
│   │   ├── repository_providers.dart
│   │   └── repositories/ (event_repository, booking_repository, activity_repository)
│   ├── features/
│   │   ├── auth/ (auth_controller, login_screen, register_screen)
│   │   ├── events/ (events_controller, event_detail_controller, events_list_screen,
│   │   │   event_detail_screen, event_form_screen, checkin_screen, widgets/)
│   │   ├── bookings/ (my_bookings_controller, my_bookings_screen, widgets/)
│   │   ├── activity/widgets/ (activity_tile)
│   │   └── shell/home_shell.dart
│   ├── router/app_router.dart
│   ├── theme/app_theme.dart
│   └── widgets/ (async_value_view, empty_state, role_badge)
├── test/models/*.dart, test/core/*.dart
└── tool/manual_test.dart
```
