<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Http\AppContext;
use App\Http\Csrf;
use App\Http\Flash;
use App\Http\Response;
use App\Mudbase\MudbaseApiError;
use App\Support\CapacityReconciler;
use App\Support\QrToken;
use App\View;

/**
 * Booking creation, cancellation, and "my bookings" — mirrors the reference app's
 * `useCreateBooking`/`useCancelBooking` (src/hooks/useBookings.ts) and `/bookings` page.
 *
 * Deliberately does NOT pre-check role/ownership before attempting a write — every mutating
 * method calls the same MudbaseClient write a permitted attendee would use and lets Mudbase's own
 * collection permissions return the real 403 if the signed-in user isn't allowed (e.g. cancelling
 * someone else's booking). See plan/build-plan.md "RBAC Matrix".
 */
final class BookingController
{
    private const MY_BOOKINGS_LIMIT = 100;

    /** @param array<string, string> $params */
    public function index(array $params): void
    {
        $ctx = AppContext::current();
        $ctx->requireSignIn('/bookings');

        $userId = $ctx->userId();
        $bookings = [];
        $eventsById = [];
        $error = null;

        try {
            $result = $ctx->mudbase->listDocuments(
                $ctx->bookingsCollectionId,
                ['userId' => $userId ?? ''],
                '-createdAt',
                1,
                self::MY_BOOKINGS_LIMIT,
            );
            $bookings = $result['data'];

            // No native join in a generic-CRUD BaaS - resolve each distinct eventId to its full
            // event doc, mirroring the reference app's useEventsByIds (src/hooks/useEvents.ts).
            $uniqueEventIds = array_values(array_unique(array_map(
                static fn (array $b): string => (string) ($b['eventId'] ?? ''),
                $bookings,
            )));
            foreach ($uniqueEventIds as $eventId) {
                if ($eventId === '') {
                    continue;
                }
                try {
                    $eventsById[$eventId] = $ctx->mudbase->getDocument($ctx->eventsCollectionId, $eventId);
                } catch (MudbaseApiError) {
                    // Event may have been deleted since the booking was made - the view renders
                    // "Event unavailable" for that row, matching BookingCard.tsx's fallback.
                }
            }
        } catch (MudbaseApiError $e) {
            $error = "Couldn't load your bookings right now: {$e->getMessage()}";
        }

        View::render('bookings/index', [
            'bookings' => $bookings,
            'eventsById' => $eventsById,
            'error' => $error,
        ]);
    }

    /**
     * Creates a booking using the capacity-race approach documented in plan/build-plan.md: decide
     * the initial status from a fresh server-side confirmed count, write it, then run the shared
     * reconciliation pass so a race against another concurrent booking self-corrects. A
     * line-for-line port of the reference app's `useCreateBooking`.
     *
     * @param array<string, string> $params
     */
    public function create(array $params): void
    {
        $ctx = AppContext::current();
        $eventId = trim((string) ($_POST['eventId'] ?? ''));
        $fallbackPath = $eventId !== '' ? '/events/' . urlencode($eventId) : '/';
        $ctx->requireSignIn($fallbackPath);
        $this->requireCsrf($fallbackPath);

        if ($eventId === '') {
            Flash::set('error', 'Choose an event to book.');
            Response::redirect('/');
        }

        $userId = $ctx->userId();
        $userName = $ctx->displayName() ?? 'Attendee';

        try {
            $event = $ctx->mudbase->getDocument($ctx->eventsCollectionId, $eventId);
            $capacity = (int) ($event['capacity'] ?? 0);

            $confirmedRes = $ctx->mudbase->listDocuments(
                $ctx->bookingsCollectionId,
                ['eventId' => $eventId, 'status' => 'confirmed'],
                '-createdAt',
                1,
                1,
            );
            $initialStatus = $confirmedRes['pagination']['total'] < $capacity ? 'confirmed' : 'waitlisted';
            $qrToken = QrToken::generate();

            $ctx->mudbase->createDocument($ctx->bookingsCollectionId, [
                'eventId' => $eventId,
                'userId' => $userId,
                'userName' => $userName,
                'status' => $initialStatus,
                'qrToken' => $qrToken,
            ]);
            $ctx->mudbase->createDocument($ctx->activityCollectionId, [
                'eventId' => $eventId,
                'actorId' => $userId,
                'actorName' => $userName,
                'action' => $initialStatus === 'confirmed' ? 'booking_confirmed' : 'booking_waitlisted',
            ]);

            CapacityReconciler::reconcile($ctx, $eventId, $capacity);

            Flash::set(
                'success',
                $initialStatus === 'confirmed'
                    ? "You're confirmed! See your ticket under My bookings."
                    : "This event is full — you've been added to the waitlist.",
            );
        } catch (MudbaseApiError $e) {
            $this->flashWriteError($e, 'book this event');
        }

        Response::redirect('/events/' . urlencode($eventId));
    }

    /**
     * Cancels an attendee's own booking, then reconciles so the earliest waitlisted booking is
     * promoted into the freed seat. A line-for-line port of the reference app's
     * `useCancelBooking`.
     *
     * @param array{id: string} $params
     */
    public function cancel(array $params): void
    {
        $ctx = AppContext::current();
        $ctx->requireSignIn('/bookings');
        $this->requireCsrf('/bookings');

        $bookingId = $params['id'];
        $userId = $ctx->userId();
        $userName = $ctx->displayName() ?? 'Attendee';

        try {
            $booking = $ctx->mudbase->getDocument($ctx->bookingsCollectionId, $bookingId);
            $eventId = (string) ($booking['eventId'] ?? '');
            $event = $ctx->mudbase->getDocument($ctx->eventsCollectionId, $eventId);
            $capacity = (int) ($event['capacity'] ?? 0);

            $ctx->mudbase->updateDocument($ctx->bookingsCollectionId, $bookingId, ['status' => 'cancelled']);
            $ctx->mudbase->createDocument($ctx->activityCollectionId, [
                'eventId' => $eventId,
                'actorId' => $userId,
                'actorName' => $userName,
                'action' => 'booking_cancelled',
            ]);

            CapacityReconciler::reconcile($ctx, $eventId, $capacity);
            Flash::set('success', 'Booking cancelled.');
        } catch (MudbaseApiError $e) {
            $this->flashWriteError($e, 'cancel this booking');
        }

        Response::redirect('/bookings');
    }

    /** Surfaces a real 403 from Mudbase's own collection permissions as a clear, non-technical flash message. */
    private function flashWriteError(MudbaseApiError $e, string $capability): void
    {
        Flash::set(
            'error',
            $e->isForbidden()
                ? "You don't have permission to {$capability}."
                : "That didn't work: {$e->getMessage()}",
        );
    }

    private function requireCsrf(string $fallbackRedirect): void
    {
        if (!Csrf::verify($_POST['_csrf'] ?? null)) {
            Flash::set('error', 'Your session expired — please try again.');
            Response::redirect($fallbackRedirect);
        }
    }
}
