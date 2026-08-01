<?php

declare(strict_types=1);

namespace App\Support;

/**
 * Renders one activity row as a plain, readable sentence for the feed. A line-for-line PHP port
 * of the reference app's `ACTIVITY_LABELS` (src/types/activity.ts) plus the actor-name prefix the
 * reference's `ActivityFeed.tsx` renders around it.
 */
final class ActivityText
{
    private const LABELS = [
        'booking_confirmed' => 'booked (confirmed)',
        'booking_waitlisted' => 'joined the waitlist',
        'booking_cancelled' => 'cancelled their booking',
        'booking_promoted' => 'was promoted from the waitlist',
        'checked_in' => 'checked in',
        'event_created' => 'created this event',
        'event_updated' => 'updated this event',
    ];

    /** @param array<string, mixed> $entry */
    public static function describe(array $entry): string
    {
        $who = is_string($entry['actorName'] ?? null) && $entry['actorName'] !== '' ? $entry['actorName'] : 'Someone';
        $action = is_string($entry['action'] ?? null) ? $entry['action'] : '';
        $label = self::LABELS[$action] ?? 'did something';

        return "{$who} {$label}";
    }
}
