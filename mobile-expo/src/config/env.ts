/**
 * All values here are read from EXPO_PUBLIC_* env vars - Expo's convention for
 * anything safe to bundle into the client binary. A project/collection id is
 * not a secret (see .env.example) - every request this app makes authenticates
 * with a real signed-in user's JWT, never a static key, and this app has no
 * anonymous/guest session at all (see plan/build-plan.md). There is no
 * server-only credential anywhere in this app, so nothing needs to live
 * outside EXPO_PUBLIC_*.
 */
function requireEnv(name: string, value: string | undefined): string {
  if (!value) {
    throw new Error(
      `Missing required environment variable: ${name}. Copy .env.example to .env and fill in your provisioned Mudbase project's IDs.`,
    );
  }
  return value;
}

export const MUDBASE_URL = process.env.EXPO_PUBLIC_MUDBASE_URL ?? "https://cloud.mudbase.dev";

export const MUDBASE_PROJECT_ID = requireEnv(
  "EXPO_PUBLIC_MUDBASE_PROJECT_ID",
  process.env.EXPO_PUBLIC_MUDBASE_PROJECT_ID,
);

export const EVENTS_COLLECTION_ID = requireEnv(
  "EXPO_PUBLIC_EVENTS_COLLECTION_ID",
  process.env.EXPO_PUBLIC_EVENTS_COLLECTION_ID,
);

export const BOOKINGS_COLLECTION_ID = requireEnv(
  "EXPO_PUBLIC_BOOKINGS_COLLECTION_ID",
  process.env.EXPO_PUBLIC_BOOKINGS_COLLECTION_ID,
);

export const ACTIVITY_COLLECTION_ID = requireEnv(
  "EXPO_PUBLIC_ACTIVITY_COLLECTION_ID",
  process.env.EXPO_PUBLIC_ACTIVITY_COLLECTION_ID,
);
