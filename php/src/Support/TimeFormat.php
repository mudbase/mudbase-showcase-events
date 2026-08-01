<?php

declare(strict_types=1);

namespace App\Support;

/** Mirrors the reference app's `formatRelativeTime`/`formatDateTime` (src/lib/utils.ts) closely enough for a demo. */
final class TimeFormat
{
    public static function relative(?string $isoDate): string
    {
        if ($isoDate === null || $isoDate === '') {
            return '';
        }

        $timestamp = strtotime($isoDate);
        if ($timestamp === false) {
            return '';
        }

        $diffSeconds = time() - $timestamp;
        if ($diffSeconds < 60) {
            return 'just now';
        }
        if ($diffSeconds < 3600) {
            $minutes = intdiv($diffSeconds, 60);
            return $minutes === 1 ? '1 minute ago' : "{$minutes} minutes ago";
        }
        if ($diffSeconds < 86400) {
            $hours = intdiv($diffSeconds, 3600);
            return $hours === 1 ? '1 hour ago' : "{$hours} hours ago";
        }
        if ($diffSeconds < 604800) {
            $days = intdiv($diffSeconds, 86400);
            return $days === 1 ? '1 day ago' : "{$days} days ago";
        }

        return date('M j, Y', $timestamp);
    }

    /** e.g. "Aug 15, 2026, 2:30 PM" — mirrors the reference app's `formatDateTime`. */
    public static function dateTime(?string $isoDate): string
    {
        if ($isoDate === null || $isoDate === '') {
            return '';
        }
        $timestamp = strtotime($isoDate);
        if ($timestamp === false) {
            return '';
        }
        return date('M j, Y, g:i A', $timestamp);
    }

    /**
     * Converts a `<input type="datetime-local">` value ("YYYY-MM-DDTHH:MM", no timezone) to a
     * full ISO 8601 date-time string, mirroring the reference app's
     * `new Date(values.startsAt).toISOString()` (which interprets the value in the browser's
     * local timezone). This server has no browser-local timezone to defer to, so it interprets
     * the value in the PHP process's own default timezone — the closest server-side equivalent —
     * and stores the resulting absolute instant.
     */
    public static function fromDateTimeLocal(string $localValue): ?string
    {
        // Browsers normally omit seconds for a plain `type="datetime-local"` input (no `step`
        // attribute), but some send them - this guard accepts either shape while still rejecting
        // anything that isn't recognizably a datetime-local value (e.g. a bare date with no time
        // component, which `strtotime()` alone would otherwise silently accept as midnight).
        if (preg_match('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/', $localValue) !== 1) {
            return null;
        }
        $timestamp = strtotime($localValue);
        if ($timestamp === false) {
            return null;
        }
        return date(\DateTime::ATOM, $timestamp);
    }

    /** Reverse of fromDateTimeLocal() — pre-fills the edit-event form's datetime-local input. */
    public static function toDateTimeLocal(?string $isoDate): string
    {
        if ($isoDate === null || $isoDate === '') {
            return '';
        }
        $timestamp = strtotime($isoDate);
        if ($timestamp === false) {
            return '';
        }
        return date('Y-m-d\TH:i', $timestamp);
    }
}
