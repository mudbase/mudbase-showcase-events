import { type ClassValue, clsx } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs))
}

export function formatRelativeTime(iso: string): string {
  const then = new Date(iso).getTime()
  const now = Date.now()
  const diffSeconds = Math.round((now - then) / 1000)

  if (Math.abs(diffSeconds) < 5) return "just now"
  if (Math.abs(diffSeconds) < 60) return `${diffSeconds}s`
  const diffMinutes = Math.round(diffSeconds / 60)
  if (Math.abs(diffMinutes) < 60) return `${diffMinutes}m`
  const diffHours = Math.round(diffMinutes / 60)
  if (Math.abs(diffHours) < 24) return `${diffHours}h`
  const diffDays = Math.round(diffHours / 24)
  if (Math.abs(diffDays) < 7) return `${diffDays}d`
  return new Intl.DateTimeFormat("en-US", { dateStyle: "medium" }).format(new Date(iso))
}

export function formatDateTime(iso: string): string {
  return new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short" }).format(new Date(iso))
}

/**
 * Converts an ISO date-time string to the value a `<input type="datetime-local">` expects
 * (local time, no timezone/seconds), for pre-filling the edit-event form.
 */
export function toDateTimeLocalValue(iso: string): string {
  const date = new Date(iso)
  const pad = (n: number): string => String(n).padStart(2, "0")
  const year = date.getFullYear()
  const month = pad(date.getMonth() + 1)
  const day = pad(date.getDate())
  const hours = pad(date.getHours())
  const minutes = pad(date.getMinutes())
  return `${year}-${month}-${day}T${hours}:${minutes}`
}

/**
 * A random, unguessable single-use check-in code. Not a security credential in the cryptographic
 * sense (this is a demo ticketing app, not a payments system) - collision resistance against
 * `crypto.randomUUID()`'s 122 bits of entropy is more than sufficient for a QR check-in token.
 */
export function generateQrToken(): string {
  return crypto.randomUUID().replace(/-/g, "")
}
