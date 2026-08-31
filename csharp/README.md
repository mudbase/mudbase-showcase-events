# Mudbase Showcase - Events (C# / ASP.NET Core)

A realtime-data event booking/ticketing app, server-rendered with **ASP.NET Core 10 Razor Pages**,
built **entirely on [Mudbase](https://www.mudbase.dev)** - auth, database, and role-based access
control - with **zero custom backend**. This is the C# port of the reference implementation in
`../web/` (Next.js): same data model, same API contract, same RBAC matrix, against the same live
project (see `plan/build-plan.md` for exactly what this build verified live end-to-end versus what
carries forward from the reference app's identical, already-completed proof - this build hit the
shared demo project's login rate limit, the same failure mode the sibling
`mudbase-showcase-kanban/csharp` port's README documents).

## Stack

ASP.NET Core 10, Razor Pages, the real [Mudbase C# SDK](https://github.com/mudbase/mudbase-sdk)
(generated client, `mudbase-sdk/csharp`), talking directly to `cloud.mudbase.dev`. There is no
database, no ORM, and no custom API of any kind in this app - every event/booking/activity read or
write goes straight to Mudbase's REST API through the generated SDK, authenticated with the
signed-in user's own JWT (held server-side in ASP.NET Core session state, never exposed to client
JS).

No client-side JS framework: inline create/edit/check-in forms use native
`<details>/<summary>` progressive disclosure where appropriate, and destructive actions use a
native `confirm()` dialog - matching the sibling Kanban port's own explicit design choice. The one
addition beyond Bootstrap's own CDN-hosted JS bundle is a single, version-pinned,
Subresource-Integrity-verified `<script>` tag for client-side QR code rendering on the "My
bookings" page (see `plan/build-plan.md` → "QR Code Rendering" for why this isn't a framework or a
build step).

## What it demonstrates

| Feature | Mudbase capability | Where |
|---|---|---|
| Two-role auth (organizer / attendee), no anonymous session | `POST /api/auth/local/login`, `GET /api/auth/session` | `Services/MudbaseAuthService.cs`, `Infrastructure/RequireMudbaseSessionMiddleware.cs` |
| Event CRUD, organizer-only writes | Collection CRUD, `events` | `Services/EventsService.cs`, `Pages/Events/New.cshtml(.cs)`, `Pages/Events/Edit.cshtml(.cs)` |
| Capacity-aware booking (confirmed vs. waitlisted) | Server-side count-check + create, `bookings` | `Services/BookingsService.cs`'s `CreateAsync` |
| Cancellation-triggered waitlist promotion | `PATCH` + reconciliation pass | `Services/CapacityService.cs`'s `ReconcileAsync`, called from `BookingsService.CancelAsync` |
| QR-code check-in | Lookup by `qrToken`, `PATCH` to `checked_in` | `Services/BookingsService.cs`'s `CheckInAsync`, `Pages/Events/CheckIn.cshtml(.cs)` |
| Per-event activity log | Collection read, `sort: "-createdAt"`, filtered by `eventId` | `Services/ActivityService.cs`, `Pages/Shared/_ActivityFeed.cshtml` |
| Role-aware UI, server-enforced | Mudbase's own per-role collection permissions | `Services/Rbac.cs`, every mutating handler across `Pages/Events/*.cshtml.cs` and `Pages/Bookings.cshtml.cs` |
| Automatic token refresh | `POST /api/auth/refresh`, single-use rotating refresh tokens | `Services/TokenRefreshHandler.cs` (ported from `mudbase-showcase-kanban/csharp`) |

## RBAC matrix

| Action | organizer | attendee |
|---|---|---|
| Read events (list + detail) | ✅ | ✅ |
| Create / update / delete an event | ✅ (own events) | ❌ |
| Book an event | ✅ (any event but their own) | ✅ |
| Cancel own booking | n/a | ✅ (own bookings only) |
| Check attendees in via QR | ✅ (own events only) | ❌ |
| Read / write activity | ✅ | ✅ |

The UI hides write controls a role/ownership can't use, and every mutating Razor Page handler
re-checks the role and ownership server-side via `Services/Rbac.cs` before calling Mudbase at all.
Neither of those is the real enforcement boundary - Mudbase's own collection permissions are, per
the live RBAC proof in `../web/plan/build-plan.md`.

## Getting started

This repo assumes a sibling clone of the Mudbase C# SDK (not published on NuGet):

```bash
cd ..                                             # parent directory of this repo
git clone https://github.com/mudbase/mudbase-sdk.git
cd mudbase-showcase-events/csharp/MudbaseShowcase.Events
dotnet run
```

Then open `http://localhost:5000` (or whatever port `dotnet run` reports). Sign in with one of the
two demo accounts via the login page's quick-fill buttons (or type credentials manually) - see
`plan/build-plan.md` for account details and the RBAC verification notes.

> **.NET version note**: this project targets `net10.0`. If your machine only has an older SDK
> installed, either install the .NET 10 SDK or see `MudbaseShowcase.Events.csproj`'s comment for
> why an older `TargetFramework` builds but will not run without a matching runtime installed.

## Configuration

No `.env` files - configuration lives in `MudbaseShowcase.Events/appsettings.json` (already
pointed at the shared demo project; none of these values are secrets - a project/collection id is
not sensitive, see `plan/build-plan.md`) or the equivalent `Mudbase__<Key>` environment variables
for a different deployment. See `appsettings.Example.json` at the repo root for the full key list.

## Provisioning (what already exists on Mudbase, not in this repo)

This app expects a Mudbase project already set up with:

1. Local auth enabled with the Multi-Role feature, two role slugs: `organizer`, `attendee`.
2. Three collections - `events`, `bookings`, `activity` - with the field shapes documented in
   `plan/build-plan.md`, and each role granted the permissions in the RBAC matrix above.

## Live verification

See `plan/build-plan.md` → "Live Verification Results" for the full account. This build verified
the entire request pipeline end-to-end (routing, antiforgery, session, DI, the real outbound HTTPS
call through the generated SDK - down to correctly parsing and displaying a real `429 Too Many
Requests` response from Mudbase's own rate limiter) live, but hit the shared demo project's login
rate limit (all ten language/platform ports in this repo family share the same demo accounts and
source IP) before a fresh `200` login could complete within this session's window. The
booking/capacity/RBAC/check-in/activity contract this port implements is carried forward from the
reference `../web/` app's identical, already-completed live verification against this exact
project/collections/roles - see that document's "Live Smoke Test Results" for the full proof.

## Known limitations (real platform constraints, not bugs)

See `plan/build-plan.md` → "Known Limitations / Design Decisions" - no registration UI (the
generated SDK doesn't expose the per-role signup endpoint the reference app's hand-rolled client
calls directly), no `PseudoObjectId.cs` (this data model has no free-typed-name-to-id field to
convert), capacity accounting is `"confirmed"`-only (not `"checked_in"`), and reconciliation is a
best-effort, non-transactional self-heal (inherent to a generic-CRUD BaaS with no cross-document
transactions).

## Relationship to the other ports

This is one of several per-language/platform reimplementations of the same reference Events app
(see `../web/README.md`). All ports share the same live Mudbase project, the same two demo
accounts, and the same data model - this port in particular mirrors
`mudbase-showcase-kanban/csharp`'s established ASP.NET Core project conventions (DI wiring,
`TokenRefreshHandler`, session-backed auth, `Rbac.cs`) rather than introducing new ones.
