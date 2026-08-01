# Mudbase Showcase — Events (Ruby / Sinatra)

A server-rendered event booking/ticketing platform built **entirely on
[Mudbase](https://www.mudbase.dev)** — auth and database, with **zero custom backend** —
implemented in **Sinatra + ERB**, talking to `cloud.mudbase.dev` through the real generated
**Mudbase Ruby SDK** (`mudbase_sdk`, module `MudbaseSDK`). This is the Ruby reimplementation of
the reference Next.js app (see `../web`): same Mudbase project, same three collections
(`events`/`bookings`/`activity`), same `organizer`/`attendee` RBAC matrix, same capacity-aware
booking + waitlist-promotion algorithm — different stack, following the Sinatra structure the
sibling `mudbase-showcase-kanban`/`mudbase-showcase-social`/`mudbase-showcase-ecommerce` ports
established.

## Stack

Sinatra 4 + ERB + `Rack::Session::Cookie`, `mudbase_sdk` (git-sourced), Puma, `rqrcode` (pure-Ruby,
server-rendered QR SVGs for the check-in flow). No ORM, no database of its own, no client-side
JavaScript — every read/write goes to Mudbase's Collections REST API, and every interaction is a
plain HTML form POST.

## What it demonstrates

| Feature | Mudbase capability | Where |
|---|---|---|
| Multi-role sign-in (organizer/attendee) | `POST /api/auth/local/login`, role-agnostic | `lib/mudbase/auth_service.rb`, `app/routes/auth_routes.rb` |
| Paginated event list with live capacity indicator | Collections, sorted + paginated reads | `app/routes/events_routes.rb`, `lib/mudbase/events_repo.rb` |
| Event CRUD — **organizer, own events only** | Ownership-scoped create/update/delete, RBAC enforced by Mudbase + this app | `app/routes/events_routes.rb` |
| Capacity-aware booking (confirmed vs waitlisted) | Server-side count read + create, self-healing reconciliation pass | `lib/mudbase/capacity.rb`, `app/routes/events_routes.rb#POST /events/:id/book` |
| Cancellation → waitlist promotion | Same reconciliation pass, re-run after cancel | `app/routes/bookings_routes.rb` |
| QR-code check-in | Server-rendered SVG (`rqrcode`) + qrToken lookup | `lib/view_helpers.rb#qr_svg`, `app/routes/events_routes.rb#POST /events/:id/checkin` |
| Per-event activity log | Append-only collection, every booking/check-in/event action appends a row | `lib/mudbase/activity_repo.rb` |
| Read-only `attendee` role on event writes | Mudbase collection permissions reject writes server-side (verified live, not just UI hiding) | see "RBAC enforcement" below |

## Provisioning (what already exists on Mudbase, not in this repo)

This app expects a Mudbase project already set up with:

1. Local auth enabled, with the Multi-Role feature configured with two role slugs:
   `organizer` / `attendee`.
2. Three collections — `events`, `bookings`, `activity` — with the field shapes documented in
   `plan/build-plan.md`. `events`: read granted to both roles, create/update/delete organizer-only.
   `bookings`: attendee can create/read/update their own bookings; organizer has full CRUD.
   `activity`: read/create granted to both roles.

`.env.example` lists every ID this app needs once that's done.

## Setup

```bash
bundle install
cp .env.example .env   # already-provisioned project values are pre-filled; add a session secret
bundle exec puma -p 4568 config.ru
# or: bundle exec rackup config.ru
```

Open `http://localhost:4568`. Sign in with one of the two demo accounts (or use the "Sign in as
Organizer / Attendee" quick-fill buttons on `/login`):

| Role | Email | Password |
|---|---|---|
| Organizer | `events.organizer.demo@gmail.com` | `DemoTest123!` |
| Attendee | `events.attendee.demo@gmail.com` | `DemoTest123!` |

### Native-extension (ffi) caveat

`mudbase_sdk` depends on `typhoeus` → `ethon` → `ffi` for its HTTP transport. `ffi`'s native
extension is loosely pinned by the SDK's own gemspec and can fail to compile against a newer
Xcode/Clang toolchain than the gem release expects. This Gemfile pins `ffi ~> 1.17` explicitly (a
version with prebuilt `arm64-darwin`/`x86_64-darwin`/Linux bottles, so `bundle install` typically
doesn't need to compile anything). If you still hit a build failure, run
`gem install ffi -v '~> 1.17'` on its own first to confirm a prebuilt binary is available for your
platform before touching the vendored SDK gemspec.

### Verifying the app

```bash
find . -name "*.rb" -not -path "./vendor/*" -exec ruby -c {} \;   # every file: Syntax OK
bundle exec ruby -e "require './app'"                             # loads cleanly, no live calls
```

## RBAC enforcement (server-side, not just UI hiding)

Every event-management route (`/events/new`, `POST /events`, `/events/:id/edit`, `POST
/events/:id`, `POST /events/:id/delete`, `/events/:id/checkin`, `POST /events/:id/checkin`) calls
`require_organizer!` (role gate) followed by `require_event_owner!` (ownership gate, comparing
`event.organizerId` to the signed-in user's id) — **before** this app ever calls Mudbase, so an
attendee manually POSTing to a route their own UI never shows a button for is rejected by this app
itself, and an organizer who doesn't own a given event is likewise rejected. Underneath this app's
own gate, Mudbase's own collection permissions are the real enforcement boundary: `events` grants
create/update/delete to the `organizer` role only. This was confirmed live both ways — see
`plan/build-plan.md` → "Live Smoke Test Results" for a raw HTTP request using a fresh attendee JWT,
issued directly by `POST /api/auth/local/login` and never touching this app's own session/cookie
machinery, that gets rejected `403` by Mudbase itself.

## Known limitations (real platform/framework constraints, not bugs)

**No push-based realtime.** This app is entirely server-rendered with no client-side JavaScript
runtime, and — like the sibling kanban/social/ecommerce ports — deliberately never sends the
Mudbase JWT to the browser (it lives only in an httponly Rack session cookie). Reload a page to
see another user's changes.

**`Mudbase Collections`' `list_data` hard-caps `limit` at 100**, client-side-enforced by the
generated SDK (confirmed by the sibling kanban/social ports' own builds). Every bounded read in
this app (`EventsRepo::LIST_LIMIT`, `BookingsRepo::LIST_LIMIT`, `ActivityRepo::LIST_LIMIT`) is set
to exactly 100 for this reason. One consequence specific to this app: the capacity reconciliation
pass (`lib/mudbase/capacity.rb`) fetches up to 100 confirmed + 100 waitlisted bookings per event —
correct for any demo-scale event, but an event whose live booking count exceeds 100 per status
would need a paginated reconciliation pass this app does not implement.

**Reconciliation is a best-effort, non-transactional self-heal**, not a hard guarantee — an
inherent property of building on a generic-CRUD BaaS with no cross-document transactions, matching
the reference web app's own documented tradeoff (see `../web/plan/build-plan.md`).

**No registration UI.** Both demo accounts already exist and are provisioned out-of-band, matching
the sibling kanban port's own scoping decision.

## Local development

```bash
bundle install
cp .env.example .env
bundle exec puma -p 4568 config.ru
```

## Deploy

Any Ruby host that runs Puma behind `config.ru` (Fly.io, Render, a bare VPS with systemd) works
unmodified. Set every variable in `.env.example` as a real environment variable —
`SESSION_SECRET` must be a long random value distinct from any other app's secret, and
`RACK_ENV=production` turns on the `secure` cookie flag (HTTPS-only session cookie).
