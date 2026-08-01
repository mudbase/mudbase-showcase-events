# Mudbase Showcase — Events (Go)

A server-rendered Go reimplementation of the reference Next.js events booking/ticketing showcase,
built **entirely on [Mudbase](https://www.mudbase.dev)** — auth, database, and role-based access
control — with **zero custom backend**. This is a sibling port of the reference web app (`../web`)
and of `mudbase-showcase-social/go` / `mudbase-showcase-kanban/go`, whose framework (net/http +
chi + `html/template`, cookie-based session, the 401 → refresh → retry pattern) this app follows
exactly — see `plan/build-plan.md` "Stack Decisions".

## Stack

Go 1.26 + `net/http` + `chi/v5` + `html/template` + `gorilla/sessions`, talking directly to
`cloud.mudbase.dev` via `github.com/mudbase/mudbase-sdk/go`. Every page is server-rendered; there
is no client-side JavaScript framework and no API route of any kind that isn't Mudbase itself — the
Mudbase JWT lives only in an encrypted, httpOnly session cookie. There is no client-side JavaScript
at all in this port (not even a poll-refresh script) — every state change is a plain HTML form POST
followed by a redirect (PRG).

## What it demonstrates

| Feature | Mudbase capability | Where |
|---|---|---|
| Two-role auth (organizer / attendee), no anonymous session | `POST /api/auth/local/login`, Multi-Role `customRole` | `internal/mbase/auth.go`, `internal/server/handlers_auth.go` |
| Event CRUD (organizer) | Collection CRUD, `events` | `internal/store/events.go`, `internal/server/handlers_events.go` |
| Capacity-aware booking (confirmed vs. waitlisted) | Server-side count via `GET .../data?filter=...` pagination total, then a write | `internal/store/bookings.go` (`Create`) |
| Race-condition self-healing via reconciliation | Re-derive confirmed/waitlisted from a fresh read, ordered by `createdAt` | `internal/store/capacity.go` (`ReconcileEventCapacity`) |
| Cancel-triggered waitlist promotion | Cancel a confirmed booking, reconcile, earliest waitlisted booking is promoted | `internal/store/bookings.go` (`Cancel`) |
| QR-code check-in | Server-rendered PNG QR (`github.com/skip2/go-qrcode`) + manual-entry lookup by `qrToken` | `internal/server/format.go` (`qrDataURI`), `internal/store/bookings.go` (`CheckIn`) |
| Reverse-chronological per-event activity log | Collection read, `sort: "-createdAt"` | `internal/store/activity.go`, event detail page |
| Role-aware UI, enforced server-side twice | This app's own `requireOrganizer` route middleware + Mudbase's own collection permissions | `internal/rbac`, `internal/server/middleware.go`, verified live below |
| 401 → refresh → retry | `POST /api/auth/refresh`, wired through every collection call via request context | `internal/mbase/refresh.go`, `internal/server/middleware.go` |

## RBAC matrix

| Action | organizer | attendee |
|---|---|---|
| Read events (list + detail) | Yes | Yes |
| Create / update / delete an event | Yes (Mudbase grants this to every organizer account for every event — a role-level, not per-document, permission; the UI additionally hides the affordance unless `event.organizerId === session.user.id`) | No |
| Create a booking | Not otherwise restricted by role; the UI hides the Book button on an organizer's own event | Yes |
| Read/cancel own booking | n/a | Yes, own bookings only (`filter.userId === session.user.id`) |
| Check attendees in via QR token | Yes (any event, per the role-level grant above; UI hides the check-in link for non-organizers) | No |
| Read activity log | Yes | Yes |
| Write activity | Yes (via event/check-in actions) | Yes (via booking actions on own bookings) |

This app enforces the matrix **twice, independently**: this app's own route-level middleware
(`requireOrganizer` in `internal/server/middleware.go`) rejects a disallowed write before any
Mudbase call is made, and Mudbase's own collection permissions independently reject the exact same
write server-side with a `403` regardless — verified live with a raw `curl` write attempt bypassing
this app's routes entirely (see "Live smoke test" below).

## Capacity-race handling

Mudbase is a generic-CRUD BaaS with no cross-document transactions or atomic counters, so a plain
"count, then decide, then create" is inherently racy. This app narrows (does not fully eliminate)
the race window with the same two-step approach as the reference web app:

1. **Decide**: count confirmed bookings for the event via the collection's real server-side
   pagination total; if under capacity, create the new booking `"confirmed"`, otherwise
   `"waitlisted"`.
2. **Reconcile**: immediately after, re-fetch every non-cancelled booking for the event
   (confirmed + waitlisted) sorted `createdAt` ascending. The first `capacity` of them are the
   ones entitled to a confirmed seat; anything past that boundary still marked `"confirmed"` is
   demoted, and anything within the boundary still marked `"waitlisted"` is promoted — each
   correction logs an activity entry.

The same reconciliation pass runs after both booking creation and cancellation, so a cancelled
confirmed seat immediately promotes the earliest waitlisted booking. It deliberately does **not**
run after check-in — capacity is defined in terms of `"confirmed"` bookings, and `checked_in` is a
distinct terminal state whose seat must not be freed while the attendee is still present. See
`internal/store/capacity.go`'s doc comment and `plan/build-plan.md`.

## Design choices carried over from the reference web app

- **Button-based actions, not drag-and-drop** — booking, cancelling, and checking in are all plain
  form submissions.
- **Zero-JS-required editing** — every page (including the create/edit event forms) is a plain
  HTML form; there is no client-side modal, no drag handle, and no JavaScript file served by this
  app at all.
- **Capacity accounting counts `"confirmed"` only, not `"checked_in"`** — see "Capacity-race
  handling" above, a deliberate reading of the task spec matching every other port of this
  showcase.

## Getting started

```bash
go build ./...
go vet ./...
cp .env.example .env   # fill in SESSION_SECRET (openssl rand -base64 32); collection IDs already
                        # point at the shared demo project
set -a; source .env; set +a
go run ./cmd/server
# → http://localhost:8080
```

Sign in with one of the two demo accounts on the login page (or type credentials manually, or
register a brand-new account under either role) — see `plan/build-plan.md` for account details and
the full RBAC verification write-up.

## Provisioning (what already exists on Mudbase, not in this repo)

This app expects a Mudbase project already set up with:

1. Local auth enabled with the Multi-Role feature, two role slugs: `organizer`, `attendee`.
2. Three collections — `events`, `bookings`, `activity` — with the field shapes documented in
   `plan/build-plan.md`, and each role granted the permissions in the RBAC matrix above.

## Live smoke test

See `plan/build-plan.md` → "Live Smoke Test Results" for the full account-by-account,
request-by-request verification against the real project: `go build`/`go vet`/`gofmt` clean,
organizer and attendee login, capacity-checked booking (confirmed → confirmed → waitlisted at a
capacity-2 event), cancellation-triggered waitlist promotion (confirmed live via the activity
feed), idempotent QR-token check-in with every rejection branch exercised (already-checked-in,
waitlisted, cancelled, not-found), and three raw `curl` requests carrying a fresh attendee JWT that
bypass this app's HTTP layer entirely — `POST`/`PATCH`/`DELETE` on `events` each rejected `403` by
Mudbase's own collection permissions (a same-token `GET` succeeds, confirming the 403s are
role/action-specific, not a broken token).

## Known limitations (real platform constraints, not bugs)

- No `users` collection — organizer/attendee names are denormalized onto `events`/`bookings` at
  write time (`organizerName`, `userName`), matching the reference web app's data model.
- No push-based realtime (no official Mudbase Go realtime client) — this app doesn't attempt a
  poll-refresh workaround either, since the events/booking flows here are not a live shared-canvas
  UI the way the kanban board is; every page reflects the state as of its own request.
- Reconciliation is a best-effort, non-transactional self-heal, not a hard guarantee — an inherent
  property of building on a generic-CRUD BaaS with no cross-document transactions.

## Environment Variables

See `.env.example`. `SESSION_SECRET` is the only real secret (signs/encrypts the session cookie);
every Mudbase ID is a plain, non-secret identifier.
