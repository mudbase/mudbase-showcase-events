# Mudbase Showcase - Events (Web)

An event booking/ticketing platform built **entirely on [Mudbase](https://www.mudbase.dev)** -
auth, database, and multi-role RBAC - with **zero custom backend**. Next.js 15 (App Router),
TypeScript strict, Tailwind CSS, shadcn/ui-style components, TanStack Query, react-hook-form + zod.

This is the reference implementation for the `mudbase-showcase-events` monorepo - see the root
[`README.md`](../README.md) for the other 9 language/platform ports.

## Features

- Multi-role auth (`organizer` / `attendee`) with JWT access + rotating refresh tokens.
- Paginated event list with a live confirmed-bookings-vs-capacity indicator.
- Capacity-aware booking: confirms while under capacity, waitlists once full, and self-corrects
  the race between two simultaneous bookings via a reconciliation pass (see
  `plan/build-plan.md` "Capacity-Race Handling Approach").
- Cancellation promotes the earliest waitlisted booking into the freed seat.
- QR-code tickets (`qrcode.react`) rendered client-side from a random `qrToken`.
- Organizer check-in flow: paste/type a scanned code, flip the matching booking to `checked_in`.
- Per-event activity log (booking confirmed/waitlisted/cancelled/promoted, checked in, event
  created/updated).

## Getting Started

```bash
npm install
cp .env.example .env.local   # already-provisioned project values are pre-filled
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

### Test accounts

Two pre-verified accounts are already provisioned on the shared Mudbase project this app talks to:

| Role | Email | Password |
|---|---|---|
| Organizer | `events.organizer.demo@gmail.com` | `DemoTest123!` |
| Attendee | `events.attendee.demo@gmail.com` | `DemoTest123!` |

## Scripts

- `npm run dev` - start the dev server
- `npm run build` - production build
- `npm run start` - run the production build
- `npm run lint` - ESLint

## Environment Variables

See `.env.example`. Every variable is `NEXT_PUBLIC_*` - there is no server-side secret anywhere in
this app (no Route Handlers, no server actions that touch a database).

## Architecture

See [`plan/build-plan.md`](./plan/build-plan.md) for the full data model, RBAC matrix, auth flow,
and capacity-race handling approach.

## License

MIT - see the repository root [LICENSE](../LICENSE).
