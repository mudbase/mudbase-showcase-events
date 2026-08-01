# Mudbase Showcase — Events (PHP)

An events booking/ticketing app built **entirely on [Mudbase](https://www.mudbase.dev)** — auth,
database, and role-based access control — with **zero custom backend**, reimplemented as a plain,
server-rendered PHP application. This is a port of the reference Next.js app in `../web`; see that
project for the canonical data model and API contract.

## Stack

Plain PHP 8.1+ (no framework — no Laravel/Symfony), PHP's built-in dev server for local
development, and the real generated `mudbase/sdk` Composer package (the same SDK used by the
sibling `mudbase-showcase-kanban/php`, `mudbase-showcase-social/php`, and
`mudbase-showcase-ecommerce/php` ports — this project mirrors that architecture: `Router` →
`Controllers` → `View` + plain `.php` view files, a request-scoped `AppContext`, and a
`MudbaseClient` wrapper around the SDK).

Auth is session-based: the Mudbase JWT pair lives in native PHP `$_SESSION`, not `localStorage` —
there is no client-side JavaScript auth flow, and in fact **no client-side JavaScript at all** in
this app. Every interaction — sign in, create/edit/delete an event, book/cancel, check in a guest
by QR token — is a plain HTML `<form>` POST. Inline confirmations (event delete) use native
`<details>/<summary>` disclosures instead of a JS `confirm()`.

## What it demonstrates

| Feature | Mudbase capability | Where |
|---|---|---|
| Two-role auth (organizer / attendee) | Multi-Role login (`POST /api/auth/local/login`, `user.customRole`) | `src/Controllers/AuthController.php`, `src/Http/AppContext.php` |
| No anonymous/guest read — every role signs in | `GET /api/auth/local/session` | `src/Http/AppContext::requireSignIn()` |
| Event CRUD, organizer-only | Collection CRUD, `events` | `src/Controllers/EventController.php` |
| Capacity-aware booking (confirmed vs. waitlisted) | Collection CRUD + a server-side count-then-decide read, `bookings` | `src/Controllers/BookingController.php::create` |
| Cancellation-triggered waitlist promotion | Re-derive + patch pass over live bookings | `src/Support/CapacityReconciler.php` |
| QR-token check-in | Filtered read + status transition | `src/Controllers/EventController.php::checkin` |
| Reverse-chronological activity log per event | Collection read, `sort: "-createdAt"` | `EventController::show`, embedded in `/events/{id}` |
| Role-aware UI, server-enforced | Mudbase's own per-role collection permissions | `src/Support/Rbac.php` |

## RBAC matrix

| Action | organizer | attendee |
|---|---|---|
| Read events (list + detail) | ✅ | ✅ |
| Create / update / delete an event | ✅ | ❌ |
| Book / cancel own booking | n/a (UI hides Book on own event) | ✅ (own bookings only) |
| Check guests in via QR token | ✅ (own events) | ❌ |
| Read / write activity | ✅ | ✅ (via own booking actions) |

`src/Support/Rbac.php` only hides/disables controls a role or non-owner cannot use in the
rendered HTML. **Controllers never pre-check role before attempting a write** — they call the
same `MudbaseClient` method a permitted role would use and let Mudbase's own collection
permissions return the real `403` if the signed-in role isn't allowed. This is the actual security
boundary — verified live (see "Live smoke test" in `plan/build-plan.md`) with a raw authenticated
request that bypasses every form this app renders.

## Getting started

This app expects the real, already-provisioned Mudbase project documented in
`plan/build-plan.md` (project id, `events`/`bookings`/`activity` collection ids).

```bash
composer install
cp .env.example .env   # fill in your own provisioned project's IDs
php -S localhost:8080 -t public public/router.php
```

Then visit `http://localhost:8080`. Sign in with one of the two demo accounts on the login page
(one-click forms, or type credentials manually) — see `plan/build-plan.md` for account details and
the RBAC verification notes.

## Live smoke test

See `plan/build-plan.md` → "Live Smoke Test Results" for the full request-by-request verification
against the real project, including a raw authenticated write attempt as the `attendee` role
proving Mudbase's own collection permissions reject an organizer-only write server-side — not
just a hidden UI form.

## Known limitations (real platform/architecture constraints, not bugs)

See `plan/build-plan.md` → "Known Limitations":

- **No realtime.** Neither this app nor the reference Next.js app subscribe to live updates on
  this project — every mutation already redirects (`303`) back to a fresh page load.
- **No cascade delete of a deleted event's bookings/activity** — matches the reference app.
- **QR image via a third-party `<img>` fetch**, not a server-generated scannable barcode — the
  plain-text `qrToken` printed alongside it is the value the check-in flow actually matches on.
- **No registration UI** — the task's two demo accounts already exist on the live project; this
  app only signs in, it never signs up.

## Design choice: forms and disclosures, not JavaScript

Booking, cancelling, and checking a guest in are all plain `<form method="post">` submits with a
CSRF token; the event-delete confirmation is a native `<details>/<summary>` disclosure. No
`@dnd-kit`-style gestures, no client JavaScript at all — a deliberate, dependency-light choice that
stays fully keyboard- and screen-reader-operable.

## Security

- CSRF token on every state-changing form, verified before any controller logic runs.
- Open-redirect guard (`Response::redirectToSafe()`) on the login `redirectTo` value.
- Session id regenerated on sign-in and sign-out.
- Every `...Id` field used in a query filter or write is a real Mudbase ObjectId — never a
  literal/placeholder string, satisfying the platform's query-sanitizer requirement.
