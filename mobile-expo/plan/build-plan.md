# Build Plan - Mudbase Showcase: Events (mobile-expo)

Generated: 2026-08-01
Mode: port (Expo/React Native port of the reference `web/` app - same project, same data)
Type: mobile, backed entirely by Mudbase (`cloud.mudbase.dev`), zero custom backend.

## Stack Decisions

- **Expo Router + TypeScript (strict) + NativeWind + TanStack Query + Zustand + Zod + react-hook-form**,
  mirroring the established architecture in the sibling `mudbase-showcase-kanban/mobile-expo` port
  exactly (same Expo/React/React Native/NativeWind/TanStack Query major versions, same file layout:
  `src/api`, `src/config`, `src/lib`, `src/stores`, `src/providers`, `src/hooks`,
  `src/components/{ui,auth,layout,events,bookings,activity}`). Reusing a proven architecture beats
  reinventing one for a sixth showcase port.
- **Real generated `mudbase-sdk` (`AuthenticationApi` + `DataApi`)**, not a hand-rolled `fetch`
  client - same choice the kanban port made and documented: every generated method takes one
  `requestParameters` object (`loginLocalUser({ loginLocalUserRequest: {...} })`), never positional
  args. `src/api/client.ts` ports the kanban port's `MudbaseClient` class verbatim for the
  auth/refresh/collection-CRUD surface, with a `getDocument` method added back in (this app needs
  single-document reads for `/events/[id]`, which the kanban board never did).
- **No drag-and-drop, no realtime/Socket.IO.** Unlike the kanban port, the web reference for this
  app has no card-dragging or Socket.IO surface to mirror in the first place - bookings/waitlist
  promotion/check-in are all plain request/response mutations with TanStack Query cache
  invalidation, not live-pushed state. Pagination on the events list is explicit Previous/Next
  buttons (`EventListScreen.tsx`), matching `web/src/components/events/EventList.tsx`'s own choice
  over infinite scroll - consistent with this app's "buttons/pickers over gestures" convention.
- **Date/time picker instead of `<input type="datetime-local">`.** React Native has no equivalent
  of the web reference's native datetime input, so `EventForm.tsx` uses
  `@react-native-community/datetimepicker` behind two buttons ("Date" / "Time"), each opening a
  native picker (`mode="date"` then `mode="time"`) that patches one shared `Date` value - buttons +
  a native picker, not a custom gesture-driven scroller, per this port's established
  "no drag-and-drop, use buttons/pickers" convention.
- **QR codes via `react-native-qrcode-svg`**, the RN equivalent of the web reference's
  `qrcode.react` `<QRCodeSVG>` - renders a booking's `qrToken` as a scannable code with no server
  round-trip, on top of the `react-native-svg` dependency this project already needs.
- **Zod v4's `z.coerce.number()` does not typecheck cleanly through `@hookform/resolvers/zod`'s
  single-generic `useForm<T>()` call** (coerce schemas type their *input* as `unknown`, distinct
  from their `number` output, and the installed resolver version cannot reconcile the two through
  one generic). `EventForm.tsx` works around this the same way a plain numeric `TextInput` has to
  anyway: the RHF-internal schema keeps `capacity` as a validated numeric-string, and only the
  external `EventFormValues` contract (what `events/new.tsx` / `events/[id]/edit.tsx` actually
  receive) exposes it as a `number`, converted in one place (`handleFormSubmit`) rather than at the
  zod-schema layer.

## No Anonymous Session (same finding as the web reference, ported forward)

Unlike `mudbase-showcase-social`'s guest-browsing bootstrap, this app has **no anonymous/guest
session and no public read** - every one of Mudbase's own collection permissions on
`events`/`bookings`/`activity` requires a real authenticated JWT, for both roles including the
attendee. `authStore.initialize()` therefore only restores an existing token pair via
`mudbaseClient.restoreTokens()` + `getSession()`; if that fails or no tokens exist, `user` stays
`null` and the root navigator redirects to `/login` - it never calls a
`createAnonymousSession()`-equivalent (that method does not exist in this port's `MudbaseClient` at
all). This exactly matches `web/src/lib/mudbase-provider.tsx`'s own "no anonymous fallback"
bootstrap.

## Data Models (identical collections, already provisioned - see `web/plan/build-plan.md` for the
full field-by-field description; not repeated here beyond what this port's Zod schemas encode)

- `events` (`6a6d3fcad07caabbbdfc5802`): `title`, `description?`, `startsAt` (ISO date-time),
  `location`, `capacity`, `organizerId`, `organizerName`.
- `bookings` (`6a6d3fcbd07caabbbdfc5819`): `eventId`, `userId`, `userName`, `status`
  (`confirmed`/`waitlisted`/`cancelled`/`checked_in`), `qrToken`.
- `activity` (`6a6d3fccd07caabbbdfc582e`): `eventId`, `actorId`, `actorName`, `action`
  (`booking_confirmed`/`booking_waitlisted`/`booking_cancelled`/`booking_promoted`/`checked_in`/
  `event_created`/`event_updated`).

Every generated `mudbase-sdk` `DataResponse`/`DataListResponse` model under-describes the actual
JSON body (`data` is typed as bare `object`) - the same generated-SDK gap the kanban port's
`schemas.ts` documents. Every document read in this app is parsed through a Zod schema in
`src/api/schemas.ts` rather than cast with `as`.

## RBAC Matrix (server-enforced; this app's own gating is UX only - see "Live Smoke Test Results" below)

| Action | organizer | attendee |
|---|---|---|
| Read events (list + detail) | yes | yes |
| Create / update / delete an event | yes (enforced server-side; the app also hides the affordance unless `event.organizerId === session.user.id`, and `events/new.tsx` / `events/[id]/edit.tsx` / `events/[id]/checkin.tsx` redirect away entirely for a non-owner) | no |
| Create a booking | UI hides the Book button on an organizer's own event | yes |
| Read/update own booking (cancel) | n/a | yes, own bookings only |
| Check others in via QR token | yes (own events) | no - UI hides the check-in link/route entirely for non-organizers |
| Read activity log | yes | yes |

`src/lib/rbac.ts` is a small helper module (`isOrganizer`, `isAttendee`, `canManageEvent`,
`roleLabel`, `isAppRole`) mirroring the role-derivation logic in `web/src/hooks/useAuth.ts`.
Server-side enforcement is the actual security boundary (Mudbase collection permissions); this
app's own `organizerId === user.id` checks are UX gating so the right people see the right buttons
- proven server-independent by the raw-`fetch` RBAC checks in the live smoke test below.

## Auth Flow

```
Cold start                      → restoreTokens() from SecureStore; if present, getSession()
                                   confirms it's still valid and returns user.customRole
No valid session                 → user stays null → root navigator redirects to /login
Login                            → POST /api/auth/local/login (via AuthenticationApi.loginLocalUser)
                                    { email, password, projectId } → token/refreshToken/user
401 on any authenticated call    → MudbaseClient refreshes once (deduped via a shared in-flight
                                    promise, since refresh tokens rotate on every use), retries the
                                    original request once, surfaces the error if that also fails
Logout                           → POST /api/auth/logout (AuthenticationApi.logoutLocalUser, best-
                                    effort) → SecureStore cleared → user null → redirected to /login
```

No registration screen - the two shared, already-verified demo accounts
(`events.organizer.demo@gmail.com` / `events.attendee.demo@gmail.com`, password `DemoTest123!`) are
the only sign-in path, matching the kanban port's own choice not to duplicate the web reference's
nice-to-have `/register` form on mobile (registration is rate-limited and shared across
concurrently-worked sibling projects; the shared seed accounts are the primary/only path here).

## Capacity-Race Handling Approach (byte-for-byte port of `web/src/lib/capacity.ts`)

Mudbase is a generic-CRUD BaaS with no cross-document transactions or atomic counters, so a plain
"count, then decide, then create" is inherently racy. `src/lib/capacity.ts`'s
`reconcileEventCapacity()` narrows (does not fully eliminate) the race window with the same
two-step approach as the web reference:

1. **Decide**: `GET bookings?filter={eventId,status:"confirmed"}&limit=1`, read `pagination.total`.
   If `total < capacity`, create the booking `"confirmed"`; otherwise `"waitlisted"`.
2. **Reconcile**: re-fetch every non-cancelled booking for the event (`confirmed` + `waitlisted`)
   sorted `createdAt` ascending. The first `capacity` of them (oldest first) are entitled to a
   confirmed seat; anything beyond that still marked `"confirmed"` is demoted to `"waitlisted"`
   (`booking_waitlisted` activity logged). Anything within the first `capacity` still marked
   `"waitlisted"` is promoted to `"confirmed"` (`booking_promoted` activity logged).

`useCreateBooking` runs this after every new booking (self-heals a race where two concurrent
requests both read the same pre-write count). `useCancelBooking` runs it after every cancellation
(promotes the earliest waitlisted booking into the freed seat). `useCheckIn` deliberately does
**not** run it - capacity is defined in terms of `"confirmed"` bookings specifically, and
check-in transitions `confirmed → checked_in`; running reconciliation there would incorrectly free
that person's seat for someone else while they're still present. This is the same deliberate scope
decision `web/plan/build-plan.md` documents, carried forward unchanged.

## Check-In Flow

`/events/[id]/checkin` (organizer-only, own events only - the screen itself redirects away for
anyone else, on top of the server-side 403 a raw request would get): a single text field for a
pasted/typed `qrToken`. On submit: `GET bookings?filter={eventId,qrToken}&limit=1`.

- No match → "not_found" - inline error, no mutation.
- Match `"checked_in"` → "already checked in" (idempotent, no mutation).
- Match `"cancelled"` → "this booking was cancelled" (no mutation).
- Match `"waitlisted"` → "waitlisted, not confirmed - cannot check in" (no mutation).
- Match `"confirmed"` → `PATCH → "checked_in"`, logs a `checked_in` activity entry, success banner
  with the attendee's name.

## Screens (Expo Router)

- `/login` - modal-presented screen: two "Organizer" / "Attendee" quick-fill buttons plus a manual
  email+password form (react-hook-form + zod, `Controller`-wrapped `TextField`s since RHF's
  `register()` does not bind to RN's `TextInput`).
- `/(tabs)/index` (`Events`) - paginated event list (`EventListScreen`, Previous/Next buttons),
  organizer-only "New event" button pinned above the list.
- `/(tabs)/bookings` (`My bookings`) - the signed-in attendee's own bookings across every event,
  each rendered with a `react-native-qrcode-svg` QR of its `qrToken` and a Cancel action
  (confirmed/waitlisted only) - a real `FlatList` since booking history is the one list in this app
  that can plausibly grow past a handful of rows.
- `/events/new` - organizer-only create form (modal presentation).
- `/events/[id]` - full detail: info, live confirmed/capacity badge, `Book` button (hidden on the
  viewer's own event), organizer-only actions (Edit / Check-in / Delete-with-confirm) when
  `organizerId === session.user.id`, and the reverse-chronological `activity` feed for the event.
- `/events/[id]/edit` - organizer-only, owner-only edit form.
- `/events/[id]/checkin` - organizer-only, owner-only manual QR-token check-in.

Both tab screens render a small `AppHeader` (title, current-user role badge, sign-out button) at
the top of their content, since Expo Router's native stack header does not carry per-role state
naturally - mirrors `web/src/components/layout/Header.tsx`'s content, adapted to sit inside each
screen instead of a persistent app shell.

## Security

- Tokens: `expo-secure-store` only (`AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY`), never `AsyncStorage` -
  identical `src/api/secureStorage.ts` to the kanban port, web fallback (`localStorage`) kept only
  for local `expo start --web` smoke-testing, clearly logged as non-production.
- Input validation: Zod schemas for every form (login, create/edit event, check-in). Event titles
  capped at 200 chars, descriptions at 2000, location at 200, capacity 1–100000 - identical limits
  to the web reference.
- Authorization: enforced server-side by Mudbase's own collection permissions (RBAC matrix above).
  This app's own role/ownership gating is UX only - see "Live Smoke Test Results" below for raw
  `fetch` write attempts as the attendee role that the UI never exposes a control for, run against
  this exact project.
- Every `...Id` field used in a query filter (`eventId`, `userId`, `organizerId`) is a real Mudbase
  ObjectId (session user id or a fetched document's `_id`) - never a literal/placeholder string.
- No secrets: every env var is `EXPO_PUBLIC_*` (a project/collection id is not a secret - every
  request authenticates with the signed-in user's own JWT, never a static credential).

## Live Smoke Test Results (2026-08-01, against the real project, via a plain-`fetch` Node harness
issuing the exact same REST request shapes this app's `src/api/client.ts` + `src/hooks/*` +
`src/lib/capacity.ts` implement - not run through the Expo app itself, since this environment has
no mobile simulator/device available; app-side gating below is verified by code inspection of the
screens/components listed, not a live UI walkthrough)

**Real platform finding hit live during this build: the login endpoint's rate limit (5 requests /
15 min / IP) is shared across every Mudbase project being tested from this network, not scoped
per-project, and - more importantly - each additional request against an already-limited window
(even a rejected `429`) appears to push the window's reset forward again rather than counting down
from a fixed start.** Running the harness from this machine's own IP, four separate attempts -
each waiting the server's own reported `retryAfter` (900s) plus a growing buffer before retrying
once - all still returned `429`, for a cumulative ~50 minutes of correctly-spaced, non-hammering
waits. This is consistent with other concurrent sibling-language ports in this same session sharing
this exact IP and demo project pool, continuously re-triggering the same window from their own
retries independent of this harness's cadence - an external condition outside this build's control,
not a bug in the retry logic (verified separately: a version of the harness that hammered the
endpoint every 45s made the same mistake worse, confirming the window is request-driven, not
wall-clock-driven).

**Resolution:** re-ran the identical, unmodified harness from `mudhaxk-vps` (a different public IP,
driven per `builder/CLAUDE.md`'s "VPS Offload" section) instead of continuing to wait out a window
this machine's IP could not clear on its own. The very first attempt from the VPS succeeded with no
rate-limiting at all, confirming the block was purely IP-scoped contention from concurrent sibling
builds on this network, not a problem with this app's request shapes or the demo accounts
themselves. Every result below is from that run.

| Step | Result |
|---|---|
| Organizer login (`events.organizer.demo@gmail.com`) | `200`, `customRole: "organizer"` |
| Attendee login (`events.attendee.demo@gmail.com`) | `200`, `customRole: "attendee"` |
| Organizer creates event A (capacity 2) + event B (capacity 2, for the race simulation) | `201` / `201` |
| Attendee reads event list (`sort=startsAt`) | `200`, both test events present |
| Organizer edits event A | `200` |
| **RBAC (raw request, bypassing the app):** attendee `POST /events` | `403` |
| **RBAC (raw request):** attendee `PATCH /events/:id` (event A) | `403` |
| **RBAC (raw request):** attendee `DELETE /events/:id` (event B) | `403` |
| Booking #1 on event A (0/2 confirmed) | decided `"confirmed"`, `201`, `booking_confirmed` logged |
| Booking #2 on event A (1/2 confirmed) | decided `"confirmed"` (fills capacity), `201`, `booking_confirmed` logged |
| Booking #3 on event A (2/2, at capacity) | decided `"waitlisted"`, `201`, `booking_waitlisted` logged |
| Reconciliation over event A after the three bookings | `0` corrections (already consistent) |
| **Race simulation** - 3 bookings force-written `"confirmed"` on event B (capacity 2) | all `201` |
| Reconciliation over event B | `1` correction - the **latest**-created booking demoted `confirmed → waitlisted`; the earliest two stayed confirmed |
| **Cancellation** - booking #2 (a confirmed seat on event A) cancelled | `200`, `booking_cancelled` logged |
| Reconciliation over event A after the cancellation | `1` correction - booking #3 (earliest waitlisted) promoted `waitlisted → confirmed`, `booking_promoted` logged |
| **Check-in** - booking #1 found by `qrToken`, `status: "confirmed"` → `PATCH → "checked_in"` | `200`, `checked_in` logged |
| Re-check-in on the same token | `"already_checked_in"` outcome, no mutation (idempotent) |
| Check-in on booking #2's token (cancelled) | `"cancelled"` outcome, no mutation |
| Check-in on an unknown token | `"not_found"` outcome, no mutation |
| Activity feed for event A (`sort=-createdAt`) | `200`, 6 entries, reverse-chronological: `checked_in → booking_promoted → booking_cancelled → booking_waitlisted → booking_confirmed → booking_confirmed` |
| Cleanup - organizer deletes both test events | `200` / `200` |
| `npx tsc --noEmit` | clean |
| `npx expo-doctor` | 20/20 checks passed |
| `npx expo export --platform web` | Metro bundled 3375 modules, no errors |

**App-side gating (verified by code inspection, not a live device run):** `app/(tabs)/index.tsx`
only renders the "New event" button when `useAuth().isOrganizer`; `app/events/new.tsx`,
`app/events/[id]/edit.tsx`, and `app/events/[id]/checkin.tsx` each redirect
(`router.back()`/`router.replace()`) away in a `useEffect` unless the signed-in user is both an
organizer and (for edit/checkin) the event's own organizer; `OrganizerActions.tsx` is only rendered
by the detail screen when `event.organizerId === user.id`. None of these are the security boundary
- the raw-request RBAC checks above prove the platform enforces the same rule independent of what
the app renders.

**Net result**: the entire app-to-Mudbase contract this app relies on - multi-role auth, event CRUD
with correctly-enforced RBAC (including a live 403 via a raw request bypassing the app), capacity-
checked booking (confirmed vs. waitlisted), race-condition self-healing via reconciliation,
cancellation-triggered waitlist promotion, and QR-token check-in with all four outcomes - is proven
correct against the real, live backend using the exact request shapes this app's hooks generate.

## Known Limitations / Design Decisions

- **No anonymous/public session** - a genuine RBAC-shape difference from the social showcase, not
  an oversight (see "No Anonymous Session" above).
- **Capacity accounting counts `"confirmed"` only, not `"checked_in"`** - a deliberate reading of
  the task's literal spec, carried forward unchanged from the web reference so every port
  implements the identical rule.
- **Reconciliation is a best-effort, non-transactional self-heal**, not a hard guarantee - inherent
  to building on a generic-CRUD BaaS with no cross-document transactions.
- **No registration screen on mobile** - the two shared demo accounts are the only sign-in path
  (see "Auth Flow" above); this matches the kanban port's own choice.

## Environment Variables

See `.env.example` - all `EXPO_PUBLIC_*` (see "Security" above for why).

## File Tree

```
mudbase-showcase-events/mobile-expo/
├── package.json, tsconfig.json, app.json, babel.config.js, metro.config.js, global.css,
│   tailwind.config.js, nativewind-env.d.ts, .env.example, .env, .gitignore
├── plan/build-plan.md
├── assets/ (icon, splash, favicon, adaptive icon layers)
├── app/
│   ├── _layout.tsx, +not-found.tsx, login.tsx
│   ├── (tabs)/_layout.tsx, index.tsx, bookings.tsx
│   └── events/new.tsx, events/[id]/index.tsx, events/[id]/edit.tsx, events/[id]/checkin.tsx
└── src/
    ├── api/ (client.ts, schemas.ts, secureStorage.ts)
    ├── config/ (env.ts)
    ├── lib/ (cn.ts, format.ts, capacity.ts, queryClient.ts, rbac.ts)
    ├── stores/ (authStore.ts)
    ├── providers/ (AppProviders.tsx)
    ├── hooks/ (useAuth.ts, useEvents.ts, useBookings.ts, useActivity.ts)
    └── components/
        ├── ui/ (Button.tsx, TextField.tsx, Card.tsx, Badge.tsx, ErrorNotice.tsx, Separator.tsx,
        │        IconButton.tsx)
        ├── auth/ (LoginForm.tsx)
        ├── layout/ (AppHeader.tsx)
        ├── events/ (EventCard.tsx, EventForm.tsx, EventListScreen.tsx, CapacityBadge.tsx,
        │            BookButton.tsx, OrganizerActions.tsx)
        ├── bookings/ (BookingCard.tsx, BookingList.tsx, CheckInForm.tsx)
        └── activity/ (ActivityFeed.tsx)
```
