function requireEnv(name: string, value: string | undefined): string {
  if (!value) throw new Error(`Missing required environment variable: ${name}`)
  return value
}

export const MUDBASE_PROJECT_ID = requireEnv(
  "NEXT_PUBLIC_MUDBASE_PROJECT_ID",
  process.env.NEXT_PUBLIC_MUDBASE_PROJECT_ID,
)
export const MUDBASE_URL = process.env.NEXT_PUBLIC_MUDBASE_URL ?? "https://cloud.mudbase.dev"

// Project publishable key - not sent on any request (see mudbase.ts / build-plan.md "Auth Flow"),
// kept only for parity with the platform dashboard and forward-compatibility.
export const MUDBASE_API_KEY = process.env.NEXT_PUBLIC_MUDBASE_API_KEY ?? ""

export const EVENTS_COLLECTION_ID = requireEnv(
  "NEXT_PUBLIC_EVENTS_COLLECTION_ID",
  process.env.NEXT_PUBLIC_EVENTS_COLLECTION_ID,
)
export const BOOKINGS_COLLECTION_ID = requireEnv(
  "NEXT_PUBLIC_BOOKINGS_COLLECTION_ID",
  process.env.NEXT_PUBLIC_BOOKINGS_COLLECTION_ID,
)
export const ACTIVITY_COLLECTION_ID = requireEnv(
  "NEXT_PUBLIC_ACTIVITY_COLLECTION_ID",
  process.env.NEXT_PUBLIC_ACTIVITY_COLLECTION_ID,
)
