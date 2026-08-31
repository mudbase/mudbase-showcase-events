# Mudbase Showcase - Events (mobile-expo)

An event booking/ticketing app built **entirely on [Mudbase](https://www.mudbase.dev)** - auth,
database, and role-based access control - with **zero custom backend**. This is the Expo/React
Native port of the reference [`../web`](../web) app: same Mudbase project, same three collections,
same RBAC matrix, same capacity/waitlist algorithm.

## Stack

Expo Router (SDK 57) + TypeScript (strict) + NativeWind + TanStack Query + Zustand + Zod +
react-hook-form, talking directly to `cloud.mudbase.dev` via the real generated
[`mudbase-sdk`](https://github.com/mudbase/mudbase-sdk) (`AuthenticationApi` + `DataApi`) - no
hand-rolled REST client, no custom backend of any kind. Every request is made with the signed-in
user's own JWT; there is no server-side code and no privileged credential anywhere in this app.

Architecture mirrors the sibling [`mudbase-showcase-kanban/mobile-expo`](../../mudbase-showcase-kanban/mobile-expo)
port: same file layout (`src/api`, `src/config`, `src/lib`, `src/stores`, `src/providers`,
`src/hooks`, `src/components/{ui,auth,layout,events,bookings,activity}`), same secure-token
pattern, same zod-validated response narrowing.

## What it demonstrates

| Feature | Mudbase capability | Where |
|---|---|---|
| Two-role auth (organizer / attendee), **no anonymous/guest session** | `POST /api/auth/local/login` via `AuthenticationApi.loginLocalUser` | `src/api/client.ts`, `src/stores/authStore.ts` |
| Event list/detail with a live confirmed-vs-capacity badge | Collection CRUD, `events` | `src/hooks/useEvents.ts`, `src/components/events/EventCard.tsx` |
| Create/edit event (organizer-only) | Collection CRUD + date/time picker | `src/components/events/EventForm.tsx` |
| Book a spot - capacity-aware confirm/waitlist decision | `bookings` create + a two-step reconciliation pass | `src/hooks/useBookings.ts`, `src/lib/capacity.ts` |
| Cancel a booking → promotes the earliest waitlisted booking | Same reconciliation pass, re-run after cancel | `src/hooks/useBookings.ts` |
| QR-code check-in (organizer scans/types a token) | `bookings` lookup by `qrToken` + status transition | `src/components/bookings/CheckInForm.tsx` |
| Reverse-chronological activity log per event | Collection read, `sort: "-createdAt"` | `src/hooks/useActivity.ts`, `src/components/activity/ActivityFeed.tsx` |
| Role-aware UI, server-enforced | Mudbase's own per-role collection permissions | `src/lib/rbac.ts`, `src/components/layout/AppHeader.tsx` |

## RBAC matrix

| Action | organizer | attendee |
|---|---|---|
| Read events (list + detail) | Yes | Yes |
| Create / update / delete an event | Yes | No |
| Book / cancel own bookings | n/a (organizer bookings not modeled) | Yes |
| Check guests in via QR token | Yes (own events) | No |

The UI hides organizer-only affordances entirely for an attendee (never a disabled button with no
explanation), and the edit/check-in/new-event screens redirect away in a `useEffect` for anyone who
isn't the right role/owner. Mudbase's own collection permissions are the real enforcement boundary
- independently verified live against this project with raw `fetch` write attempts that never go
through this app's UI at all (see `plan/build-plan.md` → "Live Smoke Test Results").

## Date/time picker + QR codes, not gestures

Mirrors this port family's deliberate choice to avoid drag-and-drop and other gesture-heavy
interactions: event start date/time is set with two native pickers
(`@react-native-community/datetimepicker`) behind plain "Date"/"Time" buttons, and a booking's
`qrToken` is rendered as a scannable code with `react-native-qrcode-svg` - both are buttons/native
pickers, not custom gesture surfaces.

## Getting started

```bash
npm install
cp .env.example .env   # already points at the shared demo project below; edit if you provision your own
npm run start           # or: npm run ios / npm run android / npm run web
```

Sign in with one of the two demo accounts on the login screen's quick-fill buttons (or type
credentials manually):

- Organizer: `events.organizer.demo@gmail.com`
- Attendee: `events.attendee.demo@gmail.com`
- Password (both): `DemoTest123!`

## Provisioning (already exists on Mudbase, not in this repo)

This app expects a Mudbase project already set up with:

1. Local auth enabled with the Multi-Role feature, two role slugs: `organizer`, `attendee`.
2. Three collections - `events`, `bookings`, `activity` - with the field shapes documented in
   `plan/build-plan.md`, each role granted the permissions in the RBAC matrix above.

`.env.example` lists every id this app needs - all values are `EXPO_PUBLIC_*` since none of them
are secret (every request authenticates with the signed-in user's own JWT, never a static key).

## Live smoke test

See `plan/build-plan.md` → "Live Smoke Test Results" for the full request-by-request verification
against the real project: login for both roles, event CRUD, RBAC 403s for the attendee (create/
update/delete an event) via raw `fetch` bypassing this app's UI entirely, the confirmed/waitlisted
booking decision, race-condition self-healing via reconciliation, cancellation-triggered waitlist
promotion, and QR-token check-in with all four outcomes (checked in / already checked in /
cancelled / not found).

## Known limitations (real platform constraints, not bugs - carried forward from the web reference)

- **No anonymous/public session.** Every role, including attendee, must sign in.
- **Capacity accounting counts `"confirmed"` bookings only, not `"checked_in"`** - a deliberate
  reading of the task's literal spec; checking someone in does not run the reconciliation pass, so
  it never "frees" their seat out from under them while they're still present at the event.
- **Reconciliation is a best-effort, non-transactional self-heal**, not a hard guarantee - inherent
  to building on a generic-CRUD BaaS with no cross-document transactions.
- **No registration screen** - sign in with one of the two demo accounts above.
