<?php

declare(strict_types=1);

namespace App\Support;

/**
 * Presentation-only helper mirroring the reference app's `CapacityBadge.tsx` threshold logic:
 * full (destructive) once confirmed reaches capacity, a warning once fewer than ~10% of seats
 * remain, otherwise a plain success/neutral badge.
 */
final class CapacityPresentation
{
    /** @return array{label: string, cssClass: string} */
    public static function describe(int $confirmed, int $capacity): array
    {
        $remaining = $capacity - $confirmed;
        if ($remaining <= 0) {
            return ['label' => "Full · {$confirmed}/{$capacity}", 'cssClass' => 'capacity-badge--full'];
        }

        $warnThreshold = max(1, (int) ceil($capacity * 0.1));
        if ($remaining <= $warnThreshold) {
            return ['label' => "{$confirmed}/{$capacity} booked", 'cssClass' => 'capacity-badge--warning'];
        }

        return ['label' => "{$confirmed}/{$capacity} booked", 'cssClass' => 'capacity-badge--ok'];
    }
}
