# Mudbase Showcase - Events (SwiftUI / iOS)

A production-shaped SwiftUI iOS app built on top of [Mudbase](https://www.mudbase.dev),
reimplementing the same reference event booking/ticketing app as the companion Next.js app in
`../web/` - same collections, same permissions model, same capacity/waitlist algorithm. Auth,
events, bookings, and check-in all talk directly to `cloud.mudbase.dev` through the real generated
Mudbase Swift SDK.

## Why SPM, not an `.xcodeproj`

This package is deliberately `.xcodeproj`-free. Since Xcode 14, you can open a `Package.swift`
directly and run an `executableTarget` that defines a SwiftUI `App` (`@main`) as a real iOS app on
a Simulator or device - Xcode synthesizes the Info.plist/bundle at build time, no project file
needed. That keeps this reimplementation's on-disk footprint identical in spirit to the other
per-language versions in this monorepo (`../web/`, `../mobile-expo/`, etc.): source + a manifest,
nothing generated or binary checked in. `swift build` from the CLI also succeeds on plain macOS -
the `platforms` list in `Package.swift` includes `.macOS(.v14)` purely so this can be verified
without Xcode (this build environment has no iOS Simulator); no UIKit-only API is used anywhere in
the target except the camera QR scanner, which is compiled only on iOS (see "Known limitations").

## Setup

1. **Clone the SDK as a sibling directory.** From the same parent directory that contains this
   monorepo (`mudbase-showcase-events/`):
   ```bash
   git clone https://github.com/mudbase/mudbase-sdk.git
   ```
   You should end up with:
   ```
   parent/
     mudbase-showcase-events/
       swift/            <- this package (Package.swift lives here)
       web/
       ...
     mudbase-sdk/
       swift/            <- the SDK package Package.swift references
       ...
   ```

2. **Create the SwiftPM identity-collision workaround symlink.** This app's own SPM package
   directory is named `swift` (see the monorepo layout above) and the SDK's own Swift subdirectory
   is *also* named `swift`. SwiftPM computes a local path dependency's package "identity" from the
   last path component of the path you give it, with no way to override that - so a plain
   `.package(path: "../../mudbase-sdk/swift")` gives this app's own package and its SDK dependency
   the *same* identity ("swift"), and dependency resolution silently conflates them. The fix is a
   relative symlink, committed at the *monorepo root* (sibling to this `swift/` directory, `web/`,
   etc.), that gives the dependency a distinct final path segment:
   ```bash
   # from mudbase-showcase-events/ (the monorepo root)
   ln -s ../mudbase-sdk/swift mudbase-sdk-swift
   ```
   `Package.swift` references `../mudbase-sdk-swift` (not `../../mudbase-sdk/swift`) for exactly
   this reason. This symlink is committed to the repo so nobody else has to rediscover this - the
   exact same workaround the ecommerce/social Swift ports in this same monorepo established first.

3. **Configure.** Copy `Config.example.plist` to `Config.plist` (same directory) and fill in your
   Mudbase project's IDs:
   ```bash
   cp Config.example.plist Config.plist
   ```
   | Key | Value |
   |---|---|
   | `MudbaseProjectId` | Your Mudbase project ID |
   | `MudbaseBaseURL` | `https://cloud.mudbase.dev` (default, rarely needs changing) |
   | `EventsCollectionId` | The `events` collection's ID |
   | `BookingsCollectionId` | The `bookings` collection's ID |
   | `ActivityCollectionId` | The `activity` collection's ID |

   None of these are secrets (a project/collection ID isn't sensitive - same rationale as
   `web/.env.example`). `Config.plist` is still gitignored to keep per-developer project IDs out of
   history. `AppConfig.load` also reads `MUDBASE_PROJECT_ID` / `MUDBASE_EVENTS_COLLECTION_ID` / etc.
   environment variables as a fallback, convenient for `swift run` during development; if neither
   source resolves every required key, the app renders a "Configuration required" screen instead of
   crashing.

4. **Open and run.**
   ```bash
   open Package.swift
   ```
   In Xcode: pick an iOS Simulator (or a physical device) as the run destination from the scheme
   selector, then Run. If you add `Config.plist` to the project navigator, make sure it's added to
   the `MudbaseShowcaseEvents` target's "Copy Bundle Resources" build phase (Xcode does this
   automatically when you drag the file in with "Add to target" checked).

   **To use the camera QR scanner** (see "What's implemented" below), also add a **Privacy - Camera
   Usage Description** (`NSCameraUsageDescription`) string under the target's Info tab - there is no
   physical Info.plist in this `.xcodeproj`-free package, so this has to be set as an Xcode build
   setting (`INFOPLIST_KEY_NSCameraUsageDescription`) the same way `Config.plist`'s bundle
   membership is a manual one-time step. Without it, iOS denies camera access at runtime and the
   scanner sheet falls back to its "camera unavailable" message - manual code entry still works.

## What's implemented

- **Auth** - email/password login and self-signup with a genuine **organizer/attendee role
  picker** (unlike the ecommerce/social ports, which only ever self-register one hardcoded role -
  this app's reference web client's `register(role, params)` takes a role parameter for exactly
  this reason). Session bootstrap from Keychain on launch, logout. Token pair stored in the
  Keychain via `Support/KeychainTokenStore.swift` - never `UserDefaults`. A 401 from an expired
  access token is transparently refreshed and retried once, for *every* authenticated call in the
  app (not just launch bootstrap) - see `Networking/AccessTokenCoordinator.swift`.
- **Events** - paginated list (soonest-first, 10/page) with a live confirmed-vs-capacity badge per
  card; full detail view; organizer-only create/edit/delete.
- **Capacity-aware booking** - creating a booking decides `confirmed` vs `waitlisted` from a fresh
  server-side confirmed count, then runs the same reconciliation pass the web app does
  (`BookingsService.reconcileCapacity`, a line-for-line port of `web/src/lib/capacity.ts`'s
  `reconcileEventCapacity`) to self-correct races. Cancelling a booking re-runs reconciliation,
  promoting the earliest waitlisted booking into the freed seat.
- **QR-code check-in** - manual paste/type entry (`CheckInView`, mirroring the web app's
  `CheckInForm.tsx` exactly, and always available on every platform) **plus** a native camera
  scanner on iOS (`QRScannerView`, AVFoundation-based - not present in the web reference at all,
  added here since a native app can reasonably use the device camera). Both paths call the same
  `BookingsService.checkIn`.
- **Activity feed** - reverse-chronological, per event: booking created/cancelled/promoted, check-
  ins, event created/updated.
- **My bookings** - the signed-in attendee's own bookings across every event, each with a
  CoreImage-rendered QR code of its `qrToken` and a Cancel action (confirmed/waitlisted only).

## Architecture

```
Sources/MudbaseShowcaseEvents/
  App/            @main entry point
  Config/         AppConfig (Config.plist + env var loader)
  Support/        Keychain, formatting, API error mapping, platform shims, QR code rendering
  Networking/     Thin wrappers over the generated SDK's async calls
  Models/         EventItem, Booking, ActivityEntry, AppUser - decoded from Mudbase JSON
  Services/       SessionStore (@MainActor ObservableObject), EventsService, BookingsService,
                  ActivityService - plain structs, the capacity/waitlist algorithm lives here
  ViewModels/     One @MainActor ObservableObject per screen
  Views/          SwiftUI views, grouped by feature area
```

`SessionStore` is the one app-wide store (created once in the `App` struct and injected via
`.environmentObject`); every other view model is constructed explicitly by its owning view (passed
`config` and, where relevant, the signed-in `AppUser`) rather than reached for via
`@EnvironmentObject`, so each screen's real dependencies stay visible at its call site - the same
convention the ecommerce/social Swift ports in this monorepo established.

## The Mudbase Swift SDK, exactly as generated

Every Mudbase call in this app goes through the real generated `MudbaseSDK` async/await methods -
each signature was read directly from `../mudbase-sdk-swift/Sources/MudbaseSDK/APIs/*.swift` before
being used, not guessed:

- `AuthenticationAPI.loginLocalUser`, `.getLocalSession`, `.refreshToken`, `.logoutLocalUser`
- `MultiRoleFeatureAPI.registerWithRole(role:registerWithRoleRequest:)`
- `DataAPI.listData` / `.getData` / `.createData` / `.updateData` / `.deleteData`

## Known platform facts baked into this build

- **`status` field writes are not blocked.** An earlier version of `mudbase-server`'s
  `middleware/fieldProtection.js` blanket-blocked any field literally named `status` on every
  project data collection for non-admin roles (the ecommerce/social ports work around this with a
  differently-named field). That bug is fixed (`mudbase-server` commit `251db188`, already deployed
  to `cloud.mudbase.dev`) - this app uses a literal `status` field on `bookings`, matching the
  reference web client exactly, with no workaround needed.
- **No native array/object field type, no native upsert, file uploads need an org role** - none of
  these constraints apply to this app's data model (events/bookings/activity are all scalar
  fields, and there's no cart-equivalent needing upsert or any image upload), so none of the
  workarounds present in the ecommerce/social ports were needed here.
- **No anonymous/public session** - this project has no public role configured (see
  `../web/plan/build-plan.md` "Auth Flow"), so an unauthenticated visitor sees the sign-in screen,
  not a bootstrapped guest session (unlike the social showcase's public feed).
- **Every `...Id`-suffixed query filter field is a real 24-char hex Mudbase ObjectId** - the
  signed-in user's session id or a fetched document's real `_id`, never a client-invented string.

## Known limitations (real platform/SDK constraints, not bugs)

- **The SwiftPM package-identity collision** described in "Setup" step 2 - a genuine SwiftPM
  constraint (identity = last path component, no override), not a bug in this app's manifest.
- **`LoginLocalUser200ResponseUser` has no `customRole`** - only `GetLocalSession200Response.user`
  (a raw `JSONValue`) carries it, so every login is followed by a `getLocalSession` call
  (`AuthGateway.currentUser()`) for exactly this reason, matching the ecommerce/social ports.
- **Certificate pinning and biometric auth are out of scope for this reference build** - the
  project's own security rules call for both on a production mobile app; they're omitted here to
  keep this a focused reimplementation of the reference booking app, not a full production
  hardening pass. Token storage (Keychain, never `UserDefaults`) is implemented, since that's a
  baseline correctness issue rather than an additive hardening feature.
- **The camera QR scanner requires manually adding `NSCameraUsageDescription`** to the Xcode run
  target's Info settings (see "Setup" step 4) - there is no physical Info.plist in this
  `.xcodeproj`-free package.

## What was and wasn't verified (read this before trusting this build)

There is **no iOS Simulator or physical device available in the environment this app was built
in** - being honest about exactly what that means for verification:

- **Verified, by a real headless integration test against the live project**
  (`Tests/ManualLiveFlowTests/ManualLiveFlowTests.swift`, run with
  `RUN_LIVE_FLOW_TEST=1 swift test --filter ManualLiveFlowTests` - disabled by default so a plain
  `swift test` never touches the network): organizer login + `customRole` check, event creation,
  attendee login + `customRole` check, event list read, booking creation deciding `confirmed`,
  a forced 3-bookings-on-capacity-2 race simulation followed by `reconcileCapacity` correctly
  demoting the excess booking back to `waitlisted`, cancellation correctly promoting a waitlisted
  booking to fill the freed seat, QR-token check-in (`confirmed → checked_in`), idempotent
  re-check-in (`already_checked_in`, no mutation), a not-found check-in, the activity feed
  containing every expected action, a genuine 401-refresh-and-retry round trip through
  `AccessTokenCoordinator` (forcing the in-memory access token invalid and confirming a call still
  succeeds via the stored refresh token), and cleanup deletion of the test event. **This run
  actually passed against the real `cloud.mudbase.dev` project** during this build (after waiting
  out a shared per-IP `/login` rate limit - `429`, `retry-after: 163` - that this same project's
  other language ports had already been exercising).
- **Verified, by `swift build` / `swift build --build-tests`**: the entire app (all Views,
  ViewModels, Services, Networking, and Models) and the test target both compile cleanly against
  the real generated SDK on macOS, with zero warnings beyond SwiftPM's own informational note about
  the test target's source path.
- **NOT verified**: anything requiring an actual rendered UI - no screenshot, no Simulator run, no
  physical-device run, no manual tap-through of the SwiftUI navigation, no verification that the
  camera QR scanner (`QRScannerView`, iOS-only) actually opens a camera preview or decodes a real
  printed/displayed QR code, no verification of Dynamic Type / accessibility / dark mode rendering,
  and no verification of `NSCameraUsageDescription` actually being wired up in a real Xcode project
  (it can't be, in this `.xcodeproj`-free CLI-only environment - see "Setup" step 4). Nothing in
  this list is fabricated or implied elsewhere in this README to have been checked - if a real
  Simulator or device becomes available, exercising the actual tab bar → event list → detail →
  book → my bookings → cancel and the organizer → new event → edit → check-in (both manual and
  camera) flows visually is the remaining verification step.

## License

MIT - see the monorepo root [LICENSE](../LICENSE).
