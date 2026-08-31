# Build Plan - Mudbase Showcase: Events (Java / Spring Boot edition)

Generated: 2026-08-01
Mode: port (Java/Spring Boot + Thymeleaf reimplementation of the Next.js reference at `../web`)
Type: server-rendered web app (fullstack via BaaS, no custom backend of any kind)
Stack: Java 17, Spring Boot 3.3 (Web MVC, not WebFlux), Thymeleaf, Bean Validation, the real
Mudbase Java SDK (`dev.mudbase:mudbase-sdk:2.0.0`), zxing (server-rendered QR code images) -
backed entirely by the same Mudbase project (`cloud.mudbase.dev`) the reference app uses.

## Stack Decisions

- Package `dev.mudbase.showcase.events`, mirroring the sibling `mudbase-showcase-kanban/java` and
  `mudbase-showcase-social/java` ports' package layout exactly: `mudbase/` (generated-SDK wrapper
  + two documented Gson-deserialization bypasses), `auth/` (session-held JWT + refresh recovery),
  `domain/` (immutable document wrappers), `support/` (RBAC-as-code, exceptions, formatting,
  redirect guard, QR rendering), `service/` (one service per collection, RBAC enforced before any
  Mudbase call), `web/` (controllers + interceptor + exception handler).
- No custom backend beyond this Spring Boot process itself: every persistence and auth concern is
  a Mudbase REST call. The JWT is held server-side in the Spring `HttpSession` (never sent to
  client JS, since there is no client JS beyond ordinary form submissions) - a stronger secrecy
  property than the reference web app's `localStorage`-held token, and the same tradeoff the
  sibling Java ports already document.
- **No registration UI.** Both demo accounts are pre-provisioned and shared across concurrently-
  worked sibling ports; adding a registration form here would only spend more of the same
  shared, rate-limited signup budget the other nine ports also depend on. Matches the sibling
  Kanban port's identical reasoning. Login ships two "Sign in as…" quick-fill buttons instead.
- **QR code rendering**: the reference web app's `<QRCodeSVG>` (client-side, `qrcode.react`) has
  no server-rendered equivalent without a real image library. `com.google.zxing:core` +
  `com.google.zxing:javase` (real Maven Central artifacts, no extra install step) render the
  booking's `qrToken` as a PNG, base64-inlined as a `data:` URI directly in the `/bookings` page -
  no extra route, no static file, no client-side dependency. The actual check-in mechanism is
  still manual paste/type of the token (see "Check-In Flow"), matching the reference exactly.
- Two-role RBAC (`organizer`/`attendee`) instead of the sibling Kanban port's three-role
  (`owner`/`member`/`viewer`) board-wide model - and unlike Kanban's single-shared-board model,
  mutation permission here is **per-document ownership**, not board-wide: an organizer may only
  edit/delete/check-in on events they themselves created. See `support/RoleSupport` and
  `EventService#requireOwnedByOrganizer`.

## Real, Already-Provisioned Mudbase Project (used as-is, not recreated)

- Base URL `https://cloud.mudbase.dev`, project ID `6a6d3fa9d07caabbbdfc564f`.
- `events` - `6a6d3fcad07caabbbdfc5802` - `title`, `description?`, `startsAt`, `location`,
  `capacity`, `organizerId`, `organizerName`.
- `bookings` - `6a6d3fcbd07caabbbdfc5819` - `eventId`, `userId`, `userName`, `status`
  (`confirmed`/`waitlisted`/`cancelled`/`checked_in`), `qrToken`.
- `activity` - `6a6d3fccd07caabbbdfc582e` - `eventId`, `actorId`, `actorName`, `action`.
- Two pre-verified shared test accounts (`events.organizer.demo@gmail.com` /
  `events.attendee.demo@gmail.com`, password `DemoTest123!`) - used directly, no new registrations
  against the shared, rate-limited signup endpoint.

## RBAC Matrix

| Action | organizer | attendee |
|---|---|---|
| Read events (list + detail) | yes | yes |
| Create an event | yes | no |
| Update / delete an event | yes, own events only (`event.organizerId == session.user.id`) | no |
| Create a booking | yes, on another organizer's event (not restricted by role - an organizer cannot book their own event, checked by ownership, not role) | yes |
| Cancel a booking | own bookings only (`booking.userId == session.user.id`) | own bookings only |
| Check others in via QR token | yes, own events only | no |
| Read activity log | yes | yes |
| Write activity | yes (via event/booking/check-in actions) | yes (via booking actions on own bookings) |

Enforced **twice, independently**: this app's own `EventService`/`BookingService` reject a
disallowed mutation with a 403 (`ForbiddenActionException`) before ever calling Mudbase, and
Mudbase's own collection permissions reject the exact same request again one layer further down
- see "Live Verification Results" below. The Thymeleaf templates additionally hide every control a
role/non-owner can't use - that's UX, not the security boundary.

## Auth Model

No anonymous/guest session, matching the sibling Kanban port and the reference web app's own
documented choice: this project's RBAC is scoped to `organizer`/`attendee` only with no public
role configured, so an unauthenticated request is redirected to `/login` instead of a silently-
bootstrapped anonymous session that would just 401/403 on every collection read anyway.
`AuthGateInterceptor` enforces this on every route except `/login`/`/logout`/static assets.

Session/refresh handling - login, logout, and the retry-once-on-401 refresh-token exchange - is
ported near-verbatim from the sibling Kanban/Social/Ecommerce Java ports, including the two real,
independently-rediscovered-and-fixed platform bugs documented in `MudbaseAuthClient`/
`MudbaseDataClient`'s javadoc:

1. **Login response Gson strict-schema bug.** `AuthenticationApi.loginLocalUser`'s generated Gson
   model hard-fails on any Multi-Role account's login response (it declares `role` but not the
   `customRole` field every Multi-Role account's response actually carries). Fixed by bypassing
   the generated method with a raw call over the SDK's own shared `OkHttpClient`, parsed leniently
   with Jackson's `ignoreUnknown` instead.
2. **List response Gson strict-schema bug.** `DataApi.listData`'s generated `Pagination` model
   hard-fails the instant the real response includes a `hasMore` field this SDK version's OpenAPI
   spec never declared. Fixed the same way - a raw list call, parsed leniently.

## Capacity-Race Handling Approach

Identical algorithm to the reference web app's `reconcileEventCapacity` (`../web/src/lib/
capacity.ts`), reimplemented in `service/CapacityReconciler`:

1. **Decide**: on booking creation, read `bookings?filter={eventId,status:"confirmed"}&limit=1`
   and compare `pagination.total` to `capacity`. If under capacity, create `"confirmed"`;
   otherwise create `"waitlisted"`.
2. **Reconcile**: immediately after, re-fetch every non-cancelled booking for the event
   (`confirmed` + `waitlisted`), sort by `createdAt` ascending. The first `capacity` of them are
   entitled to a confirmed seat; any others still `"confirmed"` are demoted to `"waitlisted"`
   (logging a `booking_waitlisted` activity entry); any within the first `capacity` still
   `"waitlisted"` are promoted to `"confirmed"` (logging `booking_promoted`). This self-heals a
   race where two concurrent requests both read the same pre-write count.

The same reconciliation runs after a booking is **cancelled**, promoting the earliest-created
waitlisted booking into the freed seat. It does **not** run after check-in - capacity is defined
in terms of `"confirmed"` bookings specifically (see `CapacityReconciler`'s javadoc), and running
it there would incorrectly free an already-seated attendee's slot.

## Check-In Flow

`/events/{id}/checkin` (organizer-only, own events only): a single text input for a pasted/typed
`qrToken`. On submit: looks up `bookings?filter={eventId,qrToken}&limit=1`.
- No match → "no booking found" message, no mutation.
- `checked_in` → "already checked in" message, no mutation (idempotent).
- `cancelled` → "this booking was cancelled" message, no mutation.
- `waitlisted` → "on the waitlist, not confirmed" message, no mutation.
- `confirmed` → updates to `checked_in`, logs a `checked_in` activity entry (attributed to the
  **guest**, not the organizer scanning them in - see `ActivityService`'s javadoc), shows success.

## Security Implementation

- Input validation: Bean Validation (`jakarta.validation`) annotations on every form DTO
  (`LoginRequest`, `EventFormRequest`, `CheckInRequest`) - caps match the reference web app's zod
  schemas exactly (title 200, description 2000, location 200, capacity 1-100000).
- Authentication: Mudbase-issued JWT (access + refresh), held server-side in the `HttpSession` -
  never reaches client JS. 401 → refresh → retry handled once via `SessionAuthService`, with the
  token-mismatch-is-not-failure fix documented in that class's javadoc.
- Authorization: enforced server-side by Mudbase's per-collection role permissions **for the
  `events` collection specifically** - confirmed live (see below) that an attendee's raw JWT is
  rejected with `403 Insufficient permissions` by Mudbase itself for `create`/`update`/`delete` on
  `events`, independent of this app.
- **Real platform finding: the `bookings` collection has no ownership enforcement at the platform
  layer.** A live raw-JWT test (organizer creates a booking owned by their own user id; attendee's
  raw JWT then `PATCH`es that booking's `status` directly against `cloud.mudbase.dev`, bypassing
  this app entirely) returned `200 OK` - Mudbase's own collection permissions allow any
  authenticated `attendee`/`organizer` to update *any* booking document, not only their own. This
  is not a bug: it is exactly the broad write grant the reference web app's `reconcileEventCapacity`
  (and this port's `CapacityReconciler`) *requires* to demote/promote bookings that belong to a
  different user during capacity reconciliation. The practical consequence: for booking
  cancellation ownership and QR check-in, **this app's own `BookingService`/`EventService`
  ownership checks are the real security boundary, not merely defense-in-depth** - ­verified live
  that `BookingService.checkIn`'s organizer+ownership check correctly rejects an attendee's
  check-in attempt with a 403 even though the identical raw `PATCH` would otherwise succeed at the
  platform layer. (Raw-JWT `DELETE` on `bookings` *is* rejected for `attendee` - `403 Insufficient
  permissions` - but this app never deletes a booking; cancellation is a status update.)
- Every `...Id` field used in a query filter or write body is a real Mudbase ObjectId (session
  user id or a fetched document's `_id`) - never a literal/placeholder string.
- Secrets: none reach the client; the only credential in this app is the server-side session JWT.

## Live Verification Results (2026-08-01, against the real project)

| Step | Result |
|---|---|
| `mvn clean install` | BUILD SUCCESS, zero warnings |
| Organizer login (`events.organizer.demo@gmail.com`) | 200, session established, role badge "Organizer" |
| Attendee login (`events.attendee.demo@gmail.com`) | 200, session established, role badge "Attendee" |
| Organizer creates event (capacity 2) | 302 redirect to `/events/{id}` - created |
| Booking #1 (attendee, 0 confirmed so far) | decided `confirmed` - capacity check against a real server-side count |
| Booking #2 (attendee, 1 confirmed so far) | decided `confirmed` - fills capacity |
| Booking #3 (attendee, 2 confirmed, at capacity) | decided `waitlisted` - capacity enforcement confirmed correct |
| Cancel booking #2 (a confirmed seat) | 302, booking #3 (earliest waitlisted) promoted `waitlisted → confirmed` - cancellation-triggered promotion confirmed correct |
| Activity feed for the event | reverse-chronological, all entries present in correct order: `event_created` → `booking_confirmed` ×2 → `booking_waitlisted` → `booking_cancelled` → `booking_promoted` |
| Check-in: confirmed booking, valid `qrToken` | `checked_in`, success message with the guest's name, `checked_in` activity logged |
| Check-in: same `qrToken` again | `already_checked_in` - idempotent, no mutation |
| Check-in: unknown `qrToken` | `not_found` - no mutation |
| Check-in: `waitlisted` booking's `qrToken` | rejected with "on the waitlist, not confirmed" - no mutation |
| **App-layer 403** - attendee `POST /events/{id}/checkin` on an event they don't organize | `403 Not allowed` - `BookingService`/`EventService`'s own `RoleSupport`+ownership check, before Mudbase is ever called |
| **App-layer 403** - attendee `POST /events` (create) | `403 Not allowed`, "Only an organizer can create an event." - see "a real bug this pass found" below |
| **App-layer 403** - attendee `POST /events/{id}/edit` on an event they don't organize | `403 Not allowed`, "Only this event's organizer can edit this event." |
| **Raw-JWT bypass 403** - attendee's raw JWT `POST`s directly to `cloud.mudbase.dev`'s `events` collection to create an event, bypassing this app entirely | `403 Insufficient permissions` (`required: {action: create, collection: events}`) - Mudbase's own RBAC, independent of this app |
| **Raw-JWT bypass 403** - attendee's raw JWT `DELETE`s a real event directly | `403 Insufficient permissions` |
| Raw-JWT: attendee's raw JWT creates their own booking directly | `201` - an allowed action, confirms the platform boundary is role/action-scoped, not a blanket deny |
| Raw-JWT: attendee's raw JWT `PATCH`es a *different user's* (organizer's) booking status directly | `200 OK` - **not** blocked; see "Real platform finding" above |
| Raw-JWT: attendee's raw JWT `DELETE`s a booking directly | `403 Insufficient permissions` - delete is more restricted than update on this collection |

See the project README for the full step-by-step reproduction commands.

### A real bug this verification pass found (and fixed)

The first live pass of the attendee-create-event test returned `200` with a soft "Couldn't create
this event, please try again" message instead of a `403` - `EventController#create` and `#update`
originally wrapped their `eventService.createEvent(...)`/`updateEvent(...)` calls in a
`catch (RuntimeException e)` block meant to catch genuine Mudbase failures, which also caught (and
silently downgraded) `ForbiddenActionException` - the exact exception `RoleSupport`'s check throws
for a disallowed role. This meant an unauthorized mutation attempt looked, to the caller, like a
transient error rather than a rejected request - precisely the kind of authorization bug this
live-verification pass exists to catch. Fixed by removing the catch entirely, matching the sibling
Kanban port's `CardController` (and this app's own `BookingController`), which never wrapped their
service calls this way: a `ForbiddenActionException`/`EventNotFoundException`/`MudbaseApiException`
must propagate to `GlobalExceptionHandler`, not be swallowed into a generic message. Re-verified
live after the fix (see table above) - now correctly returns `403`.

## Known Limitations / Design Decisions

- **No anonymous/public session** - see "Auth Model" above.
- **Capacity accounting counts `"confirmed"` only, not `"checked_in"`** - a deliberate reading of
  the task's literal spec, matching every other port's identical rule (see `CapacityReconciler`'s
  javadoc).
- **Reconciliation is a best-effort, non-transactional self-heal**, not a hard guarantee - Mudbase
  is a generic-CRUD BaaS with no cross-document transactions; this is the same category of
  tradeoff the sibling showcases document for their own check-then-act guards.
- **Event deletion does not cascade** to that event's bookings/activity rows, matching the
  reference web app's `useDeleteEvent` (a generic single-document delete, no cross-collection
  cleanup step).
- **No drag-and-drop, no realtime layer** - this is a classic server-rendered app: every mutation
  redirects back to a `GET`, which re-fetches fresh state.

## Environment Variables

See `.env.example`.

## File Tree

```
mudbase-showcase-events/java/
├── pom.xml, .env.example, .env, .gitignore, README.md
├── plan/build-plan.md
└── src/main/
    ├── java/dev/mudbase/showcase/events/
    │   ├── EventsApplication.java
    │   ├── config/ (MudbaseProperties, MudbaseClientFactory)
    │   ├── mudbase/ (AuthResult, DocumentMapper, MudbaseApiException, MudbaseAuthClient, MudbaseDataClient, PageResult)
    │   ├── auth/ (AuthSession, SessionAuthService)
    │   ├── domain/ (EventDoc, BookingDoc, ActivityEntry)
    │   ├── support/ (RoleSupport, ForbiddenActionException, EventNotFoundException, Formatting,
    │   │   RedirectSupport, ViewModelHelper, QrTokenGenerator, QrImageRenderer)
    │   ├── service/ (AuthService, EventService, BookingService, ActivityService, CapacityReconciler)
    │   └── web/ (AuthController, EventController, BookingController, AuthGateInterceptor,
    │       WebConfig, GlobalExceptionHandler, dto/)
    └── resources/
        ├── application.properties
        ├── static/css/app.css
        └── templates/ (fragments/layout, auth/login, error, index, events/{form,detail,checkin,not-found}, bookings/list)
```
