# Mudbase Showcase — Events (Java / Spring Boot edition)

An event booking/ticketing app built **entirely on [Mudbase](https://www.mudbase.dev)** — auth,
database, role-based access control, no custom backend of any kind — reimplemented in
**Spring Boot + Thymeleaf** (server-rendered, no client-side JS framework). This is a companion to
the reference Next.js app at `../web`: same Mudbase project, same three collections
(`events`/`bookings`/`activity`), same RBAC matrix, capacity/waitlist-promotion algorithm, and
QR check-in flow; see `plan/build-plan.md` for what deliberately differs (server-rendered forms
and a server-rendered QR image instead of client-side rendering, no registration UI) and why.

## Stack

Java 17, Spring Boot 3.3 (Web MVC, not WebFlux), Thymeleaf, Bean Validation, zxing (server-
rendered QR code PNGs). The only outbound HTTP this app makes is the real Mudbase Java SDK against
`cloud.mudbase.dev` — no other services, no database of its own.

## Setup

### 1. Install the Mudbase SDK to your local Maven repository (one-time, mandatory)

The SDK is **not published to Maven Central** — it lives at
[github.com/mudbase/mudbase-sdk](https://github.com/mudbase/mudbase-sdk), subdirectory `java/`.
Clone it as a **sibling** of this repo, then install it into `~/.m2`:

```bash
git clone https://github.com/mudbase/mudbase-sdk.git
cd mudbase-sdk/java && mvn install
```

This installs `dev.mudbase:mudbase-sdk:2.0.0` into your local repo — already done on any machine
that previously set up the sibling `mudbase-showcase-kanban/java`, `mudbase-showcase-social/java`,
or `mudbase-showcase-ecommerce/java` ports, since it's the exact same artifact.

### 2. Configure environment variables

```bash
cp .env.example .env
# fill in your provisioned project's IDs
set -a && source .env && set +a
```

See `.env.example` for the full list. You need a Mudbase project already provisioned with local
auth, the Multi-Role feature's two role slugs (`organizer`/`attendee`), and the three collections
(`events`, `bookings`, `activity`) shaped as documented in `../web/plan/build-plan.md` with the
RBAC matrix below — this app assumes that provisioning already exists, exactly like the reference
web app does.

### 3. Build and run

```bash
cd mudbase-showcase-events/java
mvn clean install   # verify it builds clean
mvn spring-boot:run
```

Visit `http://localhost:8080` and sign in with one of the two demo accounts (the login page ships
one-click "Sign in as Organizer/Attendee" buttons for fast demoing).

## What's implemented

| Page | Route | Notes |
|---|---|---|
| Event list | `GET /` | Paginated, `sort=startsAt`; each card shows a live confirmed/capacity badge; organizers see a "New event" CTA |
| Create event | `GET/POST /events/new`, `POST /events` | Organizer-only |
| Event detail | `GET /events/{id}` | Info, capacity badge, Book button / booking status, organizer actions, activity feed |
| Book an event | `POST /events/{id}/book` | Capacity-race approach: decide from a fresh confirmed count, then reconcile |
| Edit event | `GET/POST /events/{id}/edit` | Organizer + owner only |
| Delete event | `POST /events/{id}/delete` | Organizer + owner only; does not cascade to bookings/activity |
| Check-in | `GET/POST /events/{id}/checkin` | Organizer + owner only; manual QR-token paste/type lookup |
| My bookings | `GET /bookings` | Every booking across every event, each with a real rendered QR PNG and a Cancel action |
| Cancel a booking | `POST /bookings/{id}/cancel` | Own bookings only; re-runs capacity reconciliation |
| Login / Logout | `GET/POST /login`, `POST /logout` | Email + password, plus two quick-fill demo buttons — no registration UI |

Session/auth: the Mudbase-issued JWT is stored server-side in the Spring `HttpSession` — it is
never sent to the browser (pages are plain server-rendered HTML with a shared stylesheet, no
client JS at all beyond ordinary form submissions).

## RBAC matrix

| Action | organizer | attendee |
|---|---|---|
| Read events / bookings (own) / activity | ✅ | ✅ |
| Create an event | ✅ | ❌ |
| Edit / delete an event | ✅ (own events only) | ❌ |
| Book an event | ✅ (another organizer's event) | ✅ |
| Cancel a booking | own bookings only | own bookings only |
| Check guests in | ✅ (own events only) | ❌ |

This app's own `EventService`/`BookingService` reject a disallowed mutation with a 403
(`ForbiddenActionException`) before ever calling Mudbase. For the **`events`** collection, that is
genuine defense-in-depth: Mudbase's own collection permissions independently reject the identical
request one layer further down — verified live with a raw JWT directly against
`cloud.mudbase.dev`, bypassing this app entirely (`403 Insufficient permissions` on
create/update/delete for an `attendee`). For the **`bookings`** collection, it is *not* merely
defense-in-depth: a live raw-JWT test found that Mudbase places no ownership restriction on
`bookings` writes at all (any authenticated role can update any booking, by design — this is what
lets capacity reconciliation promote/demote a *different* user's booking). That means this app's
own ownership check in `BookingService` is the actual, load-bearing security boundary for booking
cancellation and QR check-in, not a redundant second layer. See `plan/build-plan.md` "Live
Verification Results" and "Real platform finding" for the full detail. The Thymeleaf templates
additionally hide every control a role/non-owner can't use — that's UX, not the security boundary.

## Architecture notes

- **`mudbase/`** wraps the generated SDK: `MudbaseDataClient` (thin `DataApi` wrapper with
  document-shape normalization, retry-once-on-401 via `SessionAuthService`), `MudbaseAuthClient`
  (login/refresh/logout, bypassing the generated SDK's login model for a known Gson strict-schema
  bug against this project's Multi-Role account shape), `MudbaseApiException`, `PageResult`,
  `DocumentMapper`. Ported near-verbatim from the sibling kanban/social/ecommerce Java showcases,
  since these are fixes for real bugs against the same live backend, not app-specific code.
- **`auth/`** — `AuthSession` (the signed-in identity, held in `HttpSession`) and
  `SessionAuthService`, including the already-fixed `recoverFromUnauthorized` token-mismatch
  recovery (see its javadoc for the full bug history — reused verbatim per the task's instruction,
  not rediscovered).
- **`domain/`** — `EventDoc`, `BookingDoc`, `ActivityEntry`: thin, immutable wrappers around a raw
  Mudbase document map, each with a `fromDocument(Map)` factory. `ActivityEntry#getDescription()`
  mirrors the reference web app's `ACTIVITY_LABELS` sentence-for-sentence.
- **`support/`** — `RoleSupport` (the RBAC matrix as code), `ForbiddenActionException` (this app's
  own 403), `EventNotFoundException` (this app's own 404), `RedirectSupport` (open-redirect guard
  for the `?redirect=` param), `Formatting` (date/time display + `<input type="datetime-local">`
  conversion, mirrors `../web/src/lib/utils.ts`), `QrTokenGenerator` (mirrors `generateQrToken()`),
  `QrImageRenderer` (zxing-based PNG rendering — this port's server-side equivalent of
  `<QRCodeSVG>`), `ViewModelHelper` (populates the header/role attributes every template needs).
- **`service/`** — one service per collection (`EventService`, `BookingService`, `ActivityService`)
  plus `AuthService` and `CapacityReconciler` (the capacity-race self-heal algorithm, ported from
  the reference web app's `capacity.ts`). Every mutating method takes the acting `AuthSession`
  first and enforces `RoleSupport`/ownership before touching Mudbase — this is the real,
  independent server-side enforcement layer described above.
- **`web/`** — `EventController` (list/detail/create/edit/delete/book/checkin),
  `BookingController` (my bookings + cancel), `AuthController`, `GlobalExceptionHandler` (401 →
  session-expired redirect; 403 → error page; `EventNotFoundException` → 404 page; anything else →
  generic 500 page, no internals leaked), `AuthGateInterceptor` + `WebConfig` (every route except
  `/login` requires a signed-in session — there is no anonymous/guest browsing in this app at all).

## Known limitations (real platform constraints or deliberate scope choices, not bugs)

- **No `users` collection.** Organizer/attendee display names are denormalized onto the row that
  references them at write time, matching the same constraint documented in every other showcase
  in this repo.
- **No realtime layer.** This is a classic server-rendered app: every mutation redirects back to a
  `GET`, which re-fetches fresh state. The reference web app's TanStack Query cache invalidation
  has no equivalent here, by design.
- **No registration UI.** Both demo accounts are pre-provisioned; see `plan/build-plan.md`
  "Stack Decisions".
- **Event deletion does not cascade** to that event's bookings/activity rows, matching the
  reference web app's own `useDeleteEvent`.
- **Reconciliation is a best-effort, non-transactional self-heal**, not a hard guarantee — an
  inherent property of building on a generic-CRUD BaaS with no cross-document transactions.
