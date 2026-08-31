/** Byte-for-byte port of web/src/lib/utils.ts's formatRelativeTime/formatDateTime/generateQrToken. */
export function formatRelativeTime(iso: string): string {
  const then = new Date(iso).getTime();
  const now = Date.now();
  const diffSeconds = Math.round((now - then) / 1000);

  if (Math.abs(diffSeconds) < 5) return "just now";
  if (Math.abs(diffSeconds) < 60) return `${diffSeconds}s`;
  const diffMinutes = Math.round(diffSeconds / 60);
  if (Math.abs(diffMinutes) < 60) return `${diffMinutes}m`;
  const diffHours = Math.round(diffMinutes / 60);
  if (Math.abs(diffHours) < 24) return `${diffHours}h`;
  const diffDays = Math.round(diffHours / 24);
  if (Math.abs(diffDays) < 7) return `${diffDays}d`;
  return new Intl.DateTimeFormat("en-US", { dateStyle: "medium" }).format(new Date(iso));
}

export function formatDateTime(iso: string): string {
  return new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short" }).format(new Date(iso));
}

/**
 * A random, unguessable single-use check-in code. Not a security credential in the cryptographic
 * sense (this is a demo ticketing app, not a payments system) - collision resistance against
 * `crypto.randomUUID()`'s 122 bits of entropy is more than sufficient for a QR check-in token.
 * `expo-crypto`'s `randomUUID` is not needed here - the Hermes/JSC runtime under the New
 * Architecture already exposes a spec-compliant `crypto.randomUUID()` global.
 */
export function generateQrToken(): string {
  return crypto.randomUUID().replace(/-/g, "");
}
