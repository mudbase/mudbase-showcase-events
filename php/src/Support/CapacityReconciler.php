<?php

declare(strict_types=1);

namespace App\Support;

use App\Http\AppContext;

/**
 * A line-for-line PHP port of the reference app's `reconcileEventCapacity`
 * (src/lib/capacity.ts) — re-derives which bookings for an event should hold a confirmed seat
 * versus sit on the waitlist, and patches only the ones whose current status disagrees with that
 * derivation.
 *
 * Mudbase (a generic-CRUD BaaS) has no cross-document transactions or atomic counters, so a plain
 * "count confirmed, then create" is inherently racy: two simultaneous booking requests can both
 * read the same pre-write count and both decide "there's room". This function narrows that race
 * window by re-deriving truth from a fresh read (creation-order priority: the first `capacity`
 * bookings, oldest first, among confirmed+waitlisted, are the ones entitled to a seat) and
 * correcting any booking that disagrees — whether that means demoting an overshoot back to
 * waitlisted, or promoting the earliest waitlisted booking once a cancellation frees a seat.
 *
 * Deliberately excludes "checked_in" bookings from the capacity count (see build-plan.md
 * "Capacity-Race Handling Approach") — the task's spec defines capacity in terms of `"confirmed"`
 * bookings specifically, and running this after check-in would incorrectly free an already-seated
 * attendee's slot for someone else on the waitlist.
 */
final class CapacityReconciler
{
    /** Mirrors the reference app's RECONCILE_FETCH_LIMIT — see MudbaseClient::listAllDocuments(). */
    private const RECONCILE_FETCH_LIMIT = 1000;

    public static function reconcile(AppContext $ctx, string $eventId, int $capacity): void
    {
        $confirmed = $ctx->mudbase->listAllDocuments(
            $ctx->bookingsCollectionId,
            ['eventId' => $eventId, 'status' => 'confirmed'],
            'createdAt',
            self::RECONCILE_FETCH_LIMIT,
        );
        $waitlisted = $ctx->mudbase->listAllDocuments(
            $ctx->bookingsCollectionId,
            ['eventId' => $eventId, 'status' => 'waitlisted'],
            'createdAt',
            self::RECONCILE_FETCH_LIMIT,
        );

        $live = [...$confirmed, ...$waitlisted];
        usort($live, static function (array $a, array $b): int {
            $aTime = strtotime((string) ($a['createdAt'] ?? '')) ?: 0;
            $bTime = strtotime((string) ($b['createdAt'] ?? '')) ?: 0;
            return $aTime <=> $bTime;
        });

        foreach ($live as $index => $booking) {
            $shouldBeConfirmed = $index < $capacity;
            $currentStatus = (string) ($booking['status'] ?? '');
            $bookingId = (string) ($booking['_id'] ?? '');
            $userId = (string) ($booking['userId'] ?? '');
            $userName = is_string($booking['userName'] ?? null) ? $booking['userName'] : 'Someone';

            if ($shouldBeConfirmed && $currentStatus !== 'confirmed') {
                $ctx->mudbase->updateDocument($ctx->bookingsCollectionId, $bookingId, ['status' => 'confirmed']);
                $ctx->mudbase->createDocument($ctx->activityCollectionId, [
                    'eventId' => $eventId,
                    'actorId' => $userId,
                    'actorName' => $userName,
                    'action' => 'booking_promoted',
                ]);
            } elseif (!$shouldBeConfirmed && $currentStatus !== 'waitlisted') {
                $ctx->mudbase->updateDocument($ctx->bookingsCollectionId, $bookingId, ['status' => 'waitlisted']);
                $ctx->mudbase->createDocument($ctx->activityCollectionId, [
                    'eventId' => $eventId,
                    'actorId' => $userId,
                    'actorName' => $userName,
                    'action' => 'booking_waitlisted',
                ]);
            }
        }
    }
}
