<?php

declare(strict_types=1);

namespace App\Support;

/**
 * Client-side mirror of the RBAC matrix Mudbase's own collection permissions already enforce
 * server-side (see plan/build-plan.md). Used purely to hide/disable controls a role cannot use
 * and to show a clear reason why — it is NOT the security boundary. A raw request bypassing this
 * app's views is still rejected by the platform; see the smoke test in build-plan.md. A PHP port
 * of the reference app's `useAuth()` role booleans (src/hooks/useAuth.ts).
 */
final class Rbac
{
    public static function isOrganizer(?string $role): bool
    {
        return $role === 'organizer';
    }

    public static function isAttendee(?string $role): bool
    {
        return $role === 'attendee';
    }

    /**
     * UX-only ownership gate for edit/delete/check-in affordances — organizers see these controls
     * only on events they organize themselves (see plan/build-plan.md "RBAC Matrix"). Mudbase's
     * own collection permissions are the real boundary; a raw request with an organizer token
     * against another organizer's event still succeeds or fails per the platform's actual grant,
     * independent of this check.
     */
    public static function canManageOwnEvent(?string $role, string $organizerId, ?string $userId): bool
    {
        return self::isOrganizer($role) && $userId !== null && $userId !== '' && $organizerId === $userId;
    }

    public static function roleLabel(?string $role): string
    {
        return match ($role) {
            'organizer' => 'Organizer',
            'attendee' => 'Attendee',
            default => 'Unknown',
        };
    }
}
