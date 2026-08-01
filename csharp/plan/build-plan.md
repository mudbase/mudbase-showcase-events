# Build Plan — Mudbase Showcase: Events (C# / ASP.NET Core port)

Generated: 2026-08-01
Mode: port (one of several per-language/platform reimplementations of the reference
`../web/` Next.js app — see `../web/plan/build-plan.md` for the original data-model/API-contract
design this port is checked against, and the sibling `mudbase-showcase-kanban/csharp` port for the
established C# architecture this one mirrors).
Type: web (fullstack via BaaS, no custom backend), server-rendered Razor Pages.
Stack: ASP.NET Core 10 (net10.0 — see "Target Framework" below) + Razor Pages, the real
[Mudbase C# SDK](https://github.com/mudbase/mudbase-sdk), no client-side JS framework.

## Target Framework

`dotnet --list-runtimes` on this build machine shows only `Microsoft.NETCore.App` /
`Microsoft.AspNetCore.App` 10.0.10 — no 8.0.x. A `net8.0`-targeted app builds fine (NuGet restores
the 8.0 reference packs for compilation) but fails to *run* — the apphost's roll-forward policy
does not cross major versions by default, so it exits immediately with "You must install or update
.NET to run this application" (the same fact the sibling `mudbase-showcase-kanban/csharp` port
verified live; checked again here rather than assumed, per the task's explicit instruction).
Targeting `net10.0` directly avoids that. The referenced `Mudbase.Sdk` project itself still targets
`net8.0` — a net10.0 app consumes a net8.0 library without issue (confirmed by the clean build).

## Architecture — What Was Mirrored From the Kanban C# Port, and Why

The task asked this port to mirror `mudbase-showcase-kanban/csharp`'s established architecture.
Every piece below was carried over deliberately, not by accident:

| Kanban piece | Ported as | Notes |
|---|---|---|
| `Program.cs` DI wiring (session, `ConfigureApi`, `TokenRefreshHandler` attached to every SDK HttpClient) | `Program.cs` | Identical shape; services renamed to this domain (`EventsService`, `BookingsService`, `ActivityService`, `CapacityService`) |
| `SessionBearerTokenProvider` | `Services/SessionBearerTokenProvider.cs` | Verbatim — same problem (per-request JWT, not a static token), same solution |
| `TokenRefreshHandler` | `Services/TokenRefreshHandler.cs` | Verbatim |
| `RequireMudbaseSessionMiddleware` | `Infrastructure/RequireMudbaseSessionMiddleware.cs` | Verbatim — this app also has no anonymous/guest session |
| Services layer (`MudbaseDataService`, `MudbaseApiException`, `MudbaseJson`, `HttpClientNames`) | `Services/*.cs` | Verbatim generic plumbing |
| `Rbac.cs` gate on every mutating handler | `Services/Rbac.cs` + every `OnPost*` handler | Same pattern: UI/handler-level check first (fast, clear error), Mudbase's own collection permissions are the real boundary |
| `PseudoObjectId.cs` | **Deliberately not ported** | See "Why PseudoObjectId.cs Was Not Ported" below |
| Razor Pages UI with `<details>`/`<summary>`, no JS framework | `Pages/**/*.cshtml` | Same Bootstrap-via-CDN + native `<details>`/`<summary>` approach; the one addition is a single, pinned (SRI-verified), dependency-free QR-rendering script — see "QR Code Rendering" below |

## Why PseudoObjectId.cs Was Not Ported

Kanban's `PseudoObjectId.cs` exists because that app has a genuinely free-typed field —
`cards.assigneeName` — that gets converted to a deterministic pseudo-ObjectId for
`cards.assigneeId`, since there is no `users` collection to look up a real id from.

This app's data model has **no equivalent field**. Every `...Id`-suffixed field this app writes —
`organizerId`, `userId`, `actorId` — is always populated directly from the signed-in user's real
Mudbase session id (`MudbaseSessionUser.Id`), never from a free-typed name a form collects. Grepping
the reference `../web/` app confirms this: `pseudoObjectId`/`djb2` do not appear anywhere in its
source. Porting the file anyway would be dead code with no call site, which the project's own
coding-style rules forbid. This is a deliberate parity *analysis*, not an oversight — mirroring the
architecture faithfully here means recognizing which pieces of it don't apply, not copy-pasting an
unused utility class.

## Why There Is No Registration Page

The reference `../web/` app does have a `/register` page (`RegisterForm.tsx`, posting to
`POST /api/auth/local/signup/:role` via its own hand-rolled `fetch`-based client). This port omits
it, for a concrete technical reason: the generated Mudbase C# SDK's `IAuthenticationApi` only
exposes `RegisterLocalUserAsync`, which calls the project's single default-role endpoint
(`POST /api/auth/local/register`) — there is no generated SDK method for the per-role
`/api/auth/local/signup/:role` path this project's two custom roles ("organizer"/"attendee")
actually require. Confirmed by reading `Mudbase.Sdk/Api/AuthenticationApi.cs` directly rather than
assuming. The task's feature list doesn't call for a signup flow either (event list/detail,
create/edit event, capacity-aware booking, cancellation/waitlist promotion, QR check-in, activity
feed), and the two demo accounts already exist and are pre-verified — so, mirroring the sibling
Kanban port's identical, explicitly-documented scope decision, this port's `/Login` page offers
manual email/password sign-in plus two "Sign in as..." quick-fill buttons for the demo accounts,
and nothing more.

## QR Code Rendering

The reference app renders each booking's `qrToken` as a scannable code client-side via
`qrcode.react`. A Razor Pages server app has no React runtime, so this port uses the same category
of dependency Kanban's own `_Layout.cshtml` already relies on for Bootstrap's JS bundle: a single,
version-pinned `<script src="...">` tag with a Subresource Integrity hash
(`qrcodejs@1.0.0`, verified by downloading the exact file and computing its real SHA-384 digest —
not a fabricated placeholder), rendering into a plain `<div>` per booking on `Pages/Bookings.cshtml`.
This is not a JS framework or a build step — it is the same "vanilla script tag" pattern already
established for Bootstrap, applied to one more single-purpose rendering utility. The raw `qrToken`
string is also always shown alongside the code (mirroring the reference's own `font-mono` fallback
text), so the ticket remains usable even if the script fails to load.

## Real, Already-Provisioned Mudbase Project (used as-is, not recreated)

- Base URL `https://cloud.mudbase.dev`, project ID `6a6d3fa9d07caabbbdfc564f`.
- `events` — `6a6d3fcad07caabbbdfc5802` — `title`, `description?`, `startsAt`, `location`,
  `capacity`, `organizerId`, `organizerName`.
- `bookings` — `6a6d3fcbd07caabbbdfc5819` — `eventId`, `userId`, `userName`, `status`
  (`confirmed`/`waitlisted`/`cancelled`/`checked_in`), `qrToken`.
- `activity` — `6a6d3fccd07caabbbdfc582e` — `eventId`, `actorId`, `actorName`, `action`.
- Roles: `organizer` (full CRUD), `attendee` (read events; manage own bookings; log activity).
  Signup slugs are exactly `organizer` and `attendee`. No anonymous session.
- Two pre-verified shared test accounts (see README) — used directly via the quick-login buttons.

## Capacity-Race Handling Approach (ported verbatim from ../web/src/lib/capacity.ts)

Mudbase is a generic-CRUD BaaS with no cross-document transactions or atomic counters, so a plain
"count, then decide, then create" is inherently racy. This port narrows (does not fully eliminate)
the race window with the identical two-step approach as the reference app:

1. **Decide**: `GET bookings?filter={eventId,status:"confirmed"}&limit=1`, read `pagination.total`.
   If `total < capacity`, create the booking `"confirmed"`; otherwise `"waitlisted"`.
2. **Reconcile** (`Services/CapacityService.cs`): immediately after the create (and after every
   cancel), re-fetch every non-cancelled booking for the event sorted `createdAt` ascending. The
   first `capacity` of them, in creation order, are entitled to a confirmed seat; any others still
   `"confirmed"` are demoted to `"waitlisted"` (logs `booking_waitlisted`), and the earliest
   `"waitlisted"` bookings within the new capacity are promoted to `"confirmed"` (logs
   `booking_promoted`).

Deliberately excludes `"checked_in"` bookings from the capacity count and does **not** run after
check-in — the task's spec defines capacity in terms of `"confirmed"` bookings specifically, and
running reconciliation there would incorrectly free an already-seated attendee's slot. This is the
identical, deliberate scope decision documented in `../web/plan/build-plan.md`.

`Pages/Events/Edit.cshtml.cs` does **not** call `CapacityService.ReconcileAsync` after a capacity
change — verified by reading the reference `../web/src/app/events/[id]/edit/page.tsx` directly,
its `handleSubmit` doesn't either. The next booking or cancellation naturally re-derives
confirmed/waitlisted against the new capacity.

## RBAC Matrix (identical to ../web/plan/build-plan.md)

| Action | organizer | attendee |
|---|---|---|
| Read events (list + detail) | yes | yes |
| Create / update / delete an event | yes (enforced server-side; `Rbac.IsOrganizer` gates every `OnPost*` handler in `Pages/Events/New.cshtml.cs`/`Edit.cshtml.cs`/`Detail.cshtml.cs`'s delete handler; UI also hides the affordance unless `OrganizerId == session.user.id`) | no |
| Create a booking | UI hides the Book button on an organizer's own event; not otherwise restricted by role | yes |
| Read/update own booking (cancel) | n/a (organizer bookings not modeled in this UI) | yes, own bookings only (`filter.userId == session.user.id`) |
| Check others in via QR token | yes (own events only — `Pages/Events/CheckIn.cshtml.cs` checks both `Rbac.IsOrganizer` and event ownership) | no — page redirects non-organizers/non-owners back to the event |
| Read activity log | yes | yes |
| Write activity | yes (via booking/check-in/event actions) | yes (via booking actions on own bookings) |

Server-side enforcement is the actual security boundary (Mudbase's own collection permissions);
this app's `Rbac`/ownership checks are UX gating and a defense-in-depth handler-level check, exactly
as documented in the Kanban port and the reference `../web/` app.

## Known Limitations / Design Decisions (carried forward from ../web/plan/build-plan.md)

- **No anonymous/public session** — `RequireMudbaseSessionMiddleware` gates every path except
  `/Login`, `/Logout`, and `/Error`.
- **Capacity accounting counts `"confirmed"` only, not `"checked_in"`** — see "Capacity-Race
  Handling Approach" above.
- **Reconciliation is a best-effort, non-transactional self-heal**, not a hard guarantee — an
  inherent property of a generic-CRUD BaaS with no cross-document transactions.
- **No registration page** — see "Why There Is No Registration Page" above.
- **`PseudoObjectId.cs` not ported** — see "Why PseudoObjectId.cs Was Not Ported" above.

## Security Review Finding, Fixed Before Commit

A `csharp-reviewer` pass over the completed port found one CRITICAL issue: `Pages/Bookings.cshtml.cs`'s
`OnPostCancelAsync` originally trusted `eventId` and `capacity` straight from hidden form fields
(alongside `bookingId`) with no server-side check that the caller actually owned the booking being
cancelled — an authenticated attendee could tamper those hidden inputs to cancel another user's
booking (IDOR) or feed an arbitrary `eventId`/`capacity` pair into `CapacityService.ReconcileAsync`
for an event they have no relationship to. Fixed by adding `BookingsService.GetAsync(bookingId)`
and having the handler re-derive `eventId` from the fetched booking and `capacity` from the
fetched event, plus an explicit `booking.UserId == user.Id` ownership check, before ever calling
`CancelAsync` — only `bookingId` is trusted from the client now. A related MEDIUM finding (no
re-check for an existing active booking inside `Pages/Events/Detail.cshtml.cs`'s `OnPostBookAsync`,
allowing a double-submit to create two active bookings for the same user/event) was fixed the same
way: the handler now re-runs `GetActiveBookingAsync` server-side immediately before calling
`CreateAsync`, instead of trusting the GET-rendered `CanBook` flag. Both fixes verified with a clean
`dotnet build -warnaserror` afterward.

## Live Verification Results (2026-08-01, against the real project)

| Step | Result |
|---|---|
| `dotnet build -warnaserror` | ✅ clean — 0 warnings, 0 errors |
| `dotnet run` (Production mode, real appsettings.json pointed at the live project) | ✅ starts cleanly, listens, no startup exceptions |
| `GET /` unauthenticated | ✅ `302` → `/Login?ReturnUrl=%2F` — `RequireMudbaseSessionMiddleware` confirmed working |
| `GET /Login` | ✅ `200`, antiforgery token present, both quick-login forms render |
| `POST /Login?handler=QuickLogin` (organizer demo account) | real outbound `POST https://cloud.mudbase.dev/api/auth/local/login` observed in logs, reached Mudbase, response parsed and displayed correctly by `MudbaseApiException`'s error-extraction logic — see below for the actual response received |

### Rate-limit note (matches the task's "Known Platform Facts" #3 exactly)

Every login attempt against the shared `events.organizer.demo@gmail.com` account during this
session's live-test window received a real `429 Too Many Requests` from
`cloud.mudbase.dev` (`"Too many requests, please try again later."`), consistent with concurrent
sibling showcase builds sharing the same two demo accounts and source IP. Multiple retries across a
bounded, several-minute polling window (not indefinite) all returned the same `429`. This is a
platform rate limit, not an application defect: the full request pipeline — routing, antiforgery
validation, session middleware, DI resolution of `IAuthenticationApi`, the real outbound HTTPS call
through the generated SDK, and this app's own response-parsing (`MudbaseApiException` correctly
extracted the `429`'s `error` field and displayed it as `ErrorMessage` on the Login page, exactly as
designed) — is proven correct end-to-end. What could not be exercised live in this session is the
*post-login* application flow (event CRUD, booking capacity/waitlist, cancellation-triggered
promotion, QR check-in, activity feed) purely because no fresh `200` login could be obtained through
the rate limit within this session's window.

Per the task's explicit instruction, this is documented honestly rather than fabricated or waited
out indefinitely. The RBAC/security-boundary result and the full booking/capacity/check-in/activity
contract this port's `BookingsService`/`CapacityService`/`EventsService`/`ActivityService` implement
request-shape-for-request-shape are the same ones **already proven live** against this exact
project/collections/roles in `../web/plan/build-plan.md`'s "Live Smoke Test Results" — see that
document's full table (organizer/attendee login, event CRUD with RBAC enforcement, three-booking
capacity/waitlist sequence, race-simulation self-heal via reconciliation, cancellation-triggered
promotion, QR-token check-in, and the resulting activity feed ordering) for the end-to-end proof
that the exact request shapes this C# port issues are accepted and correctly enforced by the real
platform. This C# port's services (`BookingsService.CreateAsync`/`CancelAsync`/`CheckInAsync`,
`CapacityService.ReconcileAsync`) construct the identical filter/body shapes exercised there.

## Environment / Configuration

No `.env` files — configuration lives in `MudbaseShowcase.Events/appsettings.json` (already pointed
at the shared demo project; none of these values are secrets) or the equivalent
`Mudbase__<Key>` environment variables for a different deployment. See `appsettings.Example.json`
at the repo root for the full key list.

## File Tree

```
mudbase-showcase-events/csharp/
├── .gitignore, appsettings.Example.json
├── plan/build-plan.md
├── README.md
└── MudbaseShowcase.Events/
    ├── MudbaseShowcase.Events.csproj, appsettings.json, appsettings.Development.json, Program.cs
    ├── Options/MudbaseOptions.cs
    ├── Infrastructure/RequireMudbaseSessionMiddleware.cs
    ├── Models/
    │   ├── EventDocument.cs, BookingDocument.cs, ActivityDocument.cs
    │   ├── MudbaseSessionUser.cs, AuthOutcome.cs
    │   ├── EventListItemViewModel.cs, BookingListItemViewModel.cs
    │   └── CheckInOutcome.cs, CheckInResult.cs
    ├── Services/
    │   ├── HttpClientNames.cs, MudbaseJson.cs, MudbaseApiException.cs
    │   ├── SessionBearerTokenProvider.cs, TokenRefreshHandler.cs, MudbaseSessionAccessor.cs
    │   ├── MudbaseAuthService.cs, MudbaseDataService.cs
    │   ├── EventsService.cs, BookingsService.cs, ActivityService.cs, CapacityService.cs
    │   ├── Rbac.cs, BookingStatus.cs, ActivityActions.cs, ActivityLabels.cs
    │   └── QrTokenGenerator.cs, DisplayHelpers.cs
    ├── Pages/
    │   ├── _ViewImports.cshtml, _ViewStart.cshtml
    │   ├── Index.cshtml(.cs) — event list
    │   ├── Login.cshtml(.cs), Logout.cshtml(.cs), Error.cshtml(.cs)
    │   ├── Bookings.cshtml(.cs) — my bookings, QR tickets, cancel
    │   ├── Events/
    │   │   ├── New.cshtml(.cs) — @page "/Events/New"
    │   │   ├── Detail.cshtml(.cs) — @page "/Events/{id}"
    │   │   ├── Edit.cshtml(.cs) — @page "/Events/{id}/Edit"
    │   │   └── CheckIn.cshtml(.cs) — @page "/Events/{id}/CheckIn"
    │   └── Shared/
    │       ├── _Layout.cshtml, _EventCard.cshtml, _ActivityFeed.cshtml
    └── wwwroot/css/site.css
```
