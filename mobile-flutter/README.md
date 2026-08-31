# Mudbase Showcase - Events (Flutter)

A Flutter reimplementation of the [Mudbase Showcase Events booking/ticketing platform](../web) -
multi-role RBAC (organizer/attendee), capacity-aware bookings with waitlist promotion, QR-code
check-in, and a per-event activity log - talking directly to `cloud.mudbase.dev` through the real,
generated **Mudbase Dart SDK** (`mudbase_sdk`, [github.com/mudbase/mudbase-sdk](https://github.com/mudbase/mudbase-sdk),
`dart/` subdirectory), with **zero custom backend**.

## Stack

Flutter + Dart, Riverpod (`flutter_riverpod`, no code generation) for state, go_router for
navigation, `flutter_secure_storage` for the auth token, `qr_flutter` for rendering booking QR
codes. Same architecture as the sibling `mudbase-showcase-kanban` Flutter port - see "Architecture
decisions" below for why plain Riverpod rather than `riverpod_generator`/`freezed`, and why this app
has no realtime socket layer (unlike kanban) - the reference web app for this showcase has none
either.

## Setup

The Mudbase Dart SDK is **not published to pub.dev** - `pubspec.yaml` references it as a relative
path dependency assuming a sibling-clone layout:

```yaml
mudbase_sdk:
  path: ../../mudbase-sdk/dart
```

`mobile-flutter/` sits one level inside the `mudbase-showcase-events` repo, so reaching a flat
sibling of that repo takes exactly two `../` segments (`mobile-flutter/` → `mudbase-showcase-events/`
→ parent → `mudbase-sdk/dart`).

Before anything else, clone `mudbase-sdk` as a sibling of `mudbase-showcase-events` itself (same
parent directory):

```bash
# from the directory that contains mudbase-showcase-events/
git clone https://github.com/mudbase/mudbase-sdk.git
```

So the layout looks like:

```
some-parent-dir/
├── mudbase-sdk/
│   └── dart/                  ← the SDK pubspec.yaml lives here
└── mudbase-showcase-events/
    └── mobile-flutter/        ← this app
```

Then:

```bash
cd mobile-flutter

# First time only (or after upgrading Flutter) - generates/refreshes the
# android/, ios/, etc. platform folders. Safe to re-run.
flutter create .

flutter pub get

cp dart_define.example.json dart_define.json
# dart_define.example.json already contains this showcase's real,
# already-provisioned project/collection ids (they're public, not secrets -
# see "Security" below). Override only if pointing at your own project.

flutter run --dart-define-from-file=dart_define.json
```

### Config (`--dart-define-from-file`, this project's Flutter convention)

Never a runtime `.env` file - every value is read via `String.fromEnvironment` in
`lib/config/env_config.dart`, which also defaults every key to this showcase's real,
already-provisioned project. `dart_define.example.json` documents every key:

| Key | Notes |
|---|---|
| `MUDBASE_PROJECT_ID` | Not a secret - same as the web app's `NEXT_PUBLIC_MUDBASE_PROJECT_ID`. |
| `EVENTS_COLLECTION_ID` | |
| `BOOKINGS_COLLECTION_ID` | |
| `ACTIVITY_COLLECTION_ID` | |
| `MUDBASE_BASE_URL` | Defaults to `https://cloud.mudbase.dev`. |

`main()` calls `EnvConfig.assertConfigured()` before `runApp` and fails fast with a clear message
if any required key is somehow left empty.

There is **no secret of any kind in this app** - every value above is safe to ship in a mobile
bundle (see "Security" below).

## Demo accounts

Sign in as either already-registered, already-verified role from the login screen's quick-fill
buttons, or type the credentials manually:

| Role | Email | Password |
|---|---|---|
| Organizer | `events.organizer.demo@gmail.com` | `DemoTest123!` |
| Attendee | `events.attendee.demo@gmail.com` | `DemoTest123!` |

This app also implements self-registration (`/register`, organizer/attendee role toggle) as a
nice-to-have, mirroring the reference web app's own `/register` page - the two shared accounts
above remain the primary path for this app's own live smoke test, since registration is
rate-limited and shared across concurrently-worked sibling projects.

## What it demonstrates

| Feature | Mudbase capability | Where |
|---|---|---|
| Two-role auth (organizer/attendee), no anonymous session | `POST /api/auth/local/login`, `POST /api/auth/local/signup/:role`, `GET /api/auth/session` | `lib/features/auth/`, `lib/core/rbac.dart` |
| Paginated event list with a live confirmed-vs-capacity indicator | Collection read, `events`, `sort: "startsAt"` | `lib/features/events/events_controller.dart`, `lib/features/events/widgets/` |
| Create/edit event (organizer-only, own events) | Collection CRUD, `events` | `lib/features/events/event_form_screen.dart`, `lib/data/repositories/event_repository.dart` |
| Capacity-aware booking (confirmed vs. waitlisted) with race self-healing | Collection CRUD, `bookings` + a real server-side count | `lib/features/events/event_detail_controller.dart`, `lib/core/capacity.dart` |
| Cancellation promotes the earliest waitlisted booking | Same reconciliation pass, re-run after cancel | `lib/core/capacity.dart` |
| QR-code tickets | `qr_flutter`'s `QrImageView`, rendered client-side from a random `qrToken` | `lib/features/bookings/widgets/booking_card.dart` |
| Organizer check-in flow | Booking lookup by `qrToken` within one event, `PATCH → checked_in` | `lib/features/events/checkin_screen.dart` |
| Per-event activity log | Collection read, `activity`, `sort: "-createdAt"` | `lib/features/events/event_detail_screen.dart`, `lib/features/activity/widgets/activity_tile.dart` |

## RBAC matrix

| Action | organizer | attendee |
|---|---|---|
| Read events (list + detail) | ✅ | ✅ |
| Create / update / delete an event | ✅ (server-enforced; UI also hides the affordance unless `event.organizerId == session.user.id`) | ❌ |
| Book a spot / manage own bookings | n/a (organizer bookings not modeled in this UI) | ✅ own bookings only |
| Check attendees in via QR token | ✅ (own events) | ❌ (screen not reachable) |
| Read/write activity | ✅ | ✅ (own booking actions) |

The UI hides write controls a role cannot use; Mudbase's own collection permissions are the real
enforcement boundary - verified live with raw repository calls bypassing the UI entirely, see
`plan/build-plan.md` → "Live Smoke Test Results".

## Capacity-race handling

Mudbase is a generic-CRUD BaaS with no cross-document transactions or atomic counters, so a plain
"count, then decide, then create" is inherently racy. This app narrows that race window with the
same two-step approach as the reference web app (`web/src/lib/capacity.ts`):

1. **Decide**: read a real server-side count of `confirmed` bookings for the event. If under
   capacity, create the new booking as `confirmed`; otherwise `waitlisted`.
2. **Reconcile** (`lib/core/capacity.dart`): re-fetch every non-cancelled booking for the event
   sorted by `createdAt` ascending. The first `capacity` of them (oldest first) are entitled to a
   confirmed seat; anything else still marked `confirmed` gets demoted to `waitlisted`
   (`booking_waitlisted` activity logged), and anything eligible but not yet `confirmed` gets
   promoted (`booking_promoted` activity logged).

Reconciliation runs after every booking create and cancel - **not** after check-in, since check-in
transitions `confirmed → checked_in` and capacity is defined in terms of `confirmed` bookings
specifically (see the doc comment on `reconcileEventCapacity`).

## Realtime

**None** - unlike the sibling kanban port, this app has no Socket.IO layer. The reference web app
for this showcase (`../web/src/lib/`) has no `mudbase-socket.ts` file and no realtime subscription
anywhere in its hooks; every screen here refetches on pull-to-refresh and immediately after its own
mutations, matching that reference exactly rather than inventing a realtime layer the original
doesn't have.

## Known limitations (real platform constraints, not bugs - inherited from the web app)

- **No anonymous/public session** - a genuine RBAC-shape property of this showcase (unlike the
  social showcase), not an oversight.
- **Capacity accounting counts `confirmed` only, not `checked_in`** - a deliberate reading of the
  task's literal spec, documented so every port of this showcase implements the identical rule.
- **Reconciliation is a best-effort, non-transactional self-heal**, not a hard guarantee - inherent
  to building on a generic-CRUD BaaS with no cross-document transactions.
- **Login is rate-limited (5/15 min per IP)**, shared across every language/platform port
  exercising this same demo project.

## Architecture decisions

- **Riverpod without code generation**, same reason as the sibling kanban port: this environment
  has no Flutter SDK installed to iteratively verify `build_runner` output locally - every
  provider and model here is verifiable by `dart analyze` alone (and, for the Flutter-free layer,
  actually was - see `plan/build-plan.md` "Testing Note").
- **One `EventDetailController` (family, keyed by `eventId`) bundling event + confirmed count + the
  viewer's own active booking + the activity feed** - a Flutter screen needs one `AsyncValue` to
  build against rather than four independent query hooks (the web app's `useEvent` +
  `useConfirmedCount` + `useMyBookingForEvent` + `useEventActivity`), same rationale the sibling
  kanban port's `BoardController` documents for its own combined state.
- **Infinite-scroll pagination on the events list** rather than numbered pages - the
  mobile-appropriate adaptation of the web app's `page`/`limit` query params, which this app still
  issues under the hood (`EventRepository.list`).
- **`generateQrToken()` uses 16 bytes from `Random.secure()`** (a CSPRNG) rather than the default
  `Random()`, since a booking's QR token must not be guessable by another attendee - the Dart
  equivalent of the web app's `crypto.randomUUID()`.

## Testing

`test/models/` and `test/core/` use plain `package:test` (not `flutter_test`) specifically so they
run with **plain `dart test`, independent of the Flutter SDK** - and they were: **46/46 passed**
in this build (see `plan/build-plan.md` "Testing Note" for exactly how, since this project's own
`pubspec.yaml` can't `pub get` without Flutter installed either).

```bash
dart test test/models test/core   # runs today, no Flutter SDK needed
flutter test                      # once Flutter is installed
```

`tool/manual_test.dart` is a standalone live smoke-test script against the real project - see
`plan/build-plan.md` → "Live Smoke Test Results"; it was executed for real during this build via
the scratch-package technique documented there, and will run directly with `dart run` (or
`flutter pub get` first) once Flutter is installed in a given environment.

## Verification

```bash
dart format --set-exit-if-changed .
dart analyze     # requires `flutter pub get` first once Flutter is installed
flutter test
```

## License

MIT - see the repo root [LICENSE](../LICENSE).
