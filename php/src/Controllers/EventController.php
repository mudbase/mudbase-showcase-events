<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Http\AppContext;
use App\Http\Csrf;
use App\Http\Flash;
use App\Http\Response;
use App\Mudbase\MudbaseApiError;
use App\Support\TimeFormat;
use App\View;

/**
 * Events — list/detail/create/edit/delete plus the organizer-only QR check-in flow. Mirrors the
 * reference app's `/`, `/events/new`, `/events/[id]`, `/events/[id]/edit`, `/events/[id]/checkin`.
 *
 * Deliberately does NOT pre-check role before attempting a write (no
 * `if (!Rbac::isOrganizer($ctx->role())) { ...403... }` guard anywhere below) — every mutating
 * method just calls the same MudbaseClient write a permitted role would use and lets Mudbase's own
 * collection permissions return the real 403 if the signed-in role isn't allowed. That is the
 * actual security boundary (verified live — see plan/build-plan.md); `src/Support/Rbac.php` is
 * used only in the views to hide/disable controls, never here.
 */
final class EventController
{
    private const EVENTS_PAGE_SIZE = 10;
    private const ACTIVITY_FEED_LIMIT = 50;
    private const MAX_TITLE_LENGTH = 200;
    private const MAX_DESCRIPTION_LENGTH = 2000;
    private const MAX_LOCATION_LENGTH = 200;
    private const MIN_CAPACITY = 1;
    private const MAX_CAPACITY = 100000;

    /** @param array<string, string> $params */
    public function index(array $params): void
    {
        $ctx = AppContext::current();
        $ctx->requireSignIn('/');

        $page = max(1, (int) ($_GET['page'] ?? 1));
        $error = null;
        $events = [];
        $pagination = ['page' => 1, 'limit' => self::EVENTS_PAGE_SIZE, 'total' => 0, 'totalPages' => 1];
        $confirmedByEventId = [];

        try {
            $result = $ctx->mudbase->listDocuments($ctx->eventsCollectionId, null, 'startsAt', $page, self::EVENTS_PAGE_SIZE);
            $events = $result['data'];
            $pagination = $result['pagination'];
            foreach ($events as $event) {
                $eventId = (string) $event['_id'];
                $confirmedByEventId[$eventId] = $this->confirmedCount($ctx, $eventId);
            }
        } catch (MudbaseApiError $e) {
            $error = "Couldn't load events right now: {$e->getMessage()}";
        }

        View::render('events/index', [
            'events' => $events,
            'pagination' => $pagination,
            'confirmedByEventId' => $confirmedByEventId,
            'error' => $error,
        ]);
    }

    /** @param array<string, string> $params */
    public function newForm(array $params): void
    {
        $ctx = AppContext::current();
        $ctx->requireSignIn('/events/new');

        View::render('events/new', ['errorMessage' => null]);
    }

    /** @param array<string, string> $params */
    public function create(array $params): void
    {
        $ctx = AppContext::current();
        $ctx->requireSignIn('/events/new');
        $this->requireCsrf('/events/new');

        [$fields, $validationError] = $this->readAndValidateForm();
        if ($validationError !== null) {
            Flash::set('error', $validationError);
            Response::redirect('/events/new');
        }

        $organizerId = $ctx->userId();
        $organizerName = $ctx->displayName() ?? 'Organizer';
        if ($organizerId === null) {
            Flash::set('error', 'You must be signed in to create an event.');
            Response::redirect('/login');
        }

        try {
            $created = $ctx->mudbase->createDocument($ctx->eventsCollectionId, [
                ...$fields,
                'organizerId' => $organizerId,
                'organizerName' => $organizerName,
            ]);
            $ctx->mudbase->createDocument($ctx->activityCollectionId, [
                'eventId' => (string) $created['_id'],
                'actorId' => $organizerId,
                'actorName' => $organizerName,
                'action' => 'event_created',
            ]);
        } catch (MudbaseApiError $e) {
            $this->flashWriteError($e, 'create events');
            Response::redirect('/events/new');
        }

        Response::redirect('/events/' . urlencode((string) $created['_id']));
    }

    /** @param array{id: string} $params */
    public function show(array $params): void
    {
        $ctx = AppContext::current();
        $eventId = $params['id'];
        $ctx->requireSignIn("/events/{$eventId}");

        try {
            $event = $ctx->mudbase->getDocument($ctx->eventsCollectionId, $eventId);
        } catch (MudbaseApiError $e) {
            Flash::set('error', $e->isNotFound() ? 'That event no longer exists.' : "Couldn't load that event: {$e->getMessage()}");
            Response::redirect('/');
        }

        $confirmed = $this->confirmedCount($ctx, $eventId);

        $myBooking = null;
        $userId = $ctx->userId();
        if ($userId !== null) {
            $myBookingResult = $ctx->mudbase->listDocuments(
                $ctx->bookingsCollectionId,
                ['eventId' => $eventId, 'userId' => $userId],
                '-createdAt',
                1,
                1,
            );
            $candidate = $myBookingResult['data'][0] ?? null;
            $myBooking = is_array($candidate) && ($candidate['status'] ?? null) !== 'cancelled' ? $candidate : null;
        }

        $activityError = null;
        $activity = [];
        try {
            $activityResult = $ctx->mudbase->listDocuments(
                $ctx->activityCollectionId,
                ['eventId' => $eventId],
                '-createdAt',
                1,
                self::ACTIVITY_FEED_LIMIT,
            );
            $activity = $activityResult['data'];
        } catch (MudbaseApiError $e) {
            $activityError = "Couldn't load the activity feed right now: {$e->getMessage()}";
        }

        View::render('events/show', [
            'event' => $event,
            'confirmed' => $confirmed,
            'myBooking' => $myBooking,
            'activity' => $activity,
            'activityError' => $activityError,
        ]);
    }

    /** @param array{id: string} $params */
    public function editForm(array $params): void
    {
        $ctx = AppContext::current();
        $eventId = $params['id'];
        $ctx->requireSignIn("/events/{$eventId}/edit");

        try {
            $event = $ctx->mudbase->getDocument($ctx->eventsCollectionId, $eventId);
        } catch (MudbaseApiError $e) {
            Flash::set('error', $e->isNotFound() ? 'That event no longer exists.' : "Couldn't load that event: {$e->getMessage()}");
            Response::redirect('/');
        }

        View::render('events/edit', ['event' => $event, 'errorMessage' => null]);
    }

    /** @param array{id: string} $params */
    public function update(array $params): void
    {
        $ctx = AppContext::current();
        $eventId = $params['id'];
        $ctx->requireSignIn("/events/{$eventId}/edit");
        $this->requireCsrf("/events/{$eventId}/edit");

        [$fields, $validationError] = $this->readAndValidateForm();
        if ($validationError !== null) {
            Flash::set('error', $validationError);
            Response::redirect("/events/{$eventId}/edit");
        }

        $actorId = $ctx->userId();
        $actorName = $ctx->displayName() ?? 'Organizer';

        try {
            $ctx->mudbase->updateDocument($ctx->eventsCollectionId, $eventId, $fields);
            $ctx->mudbase->createDocument($ctx->activityCollectionId, [
                'eventId' => $eventId,
                'actorId' => $actorId,
                'actorName' => $actorName,
                'action' => 'event_updated',
            ]);
        } catch (MudbaseApiError $e) {
            $this->flashWriteError($e, 'edit this event');
            Response::redirect("/events/{$eventId}/edit");
        }

        Response::redirect("/events/{$eventId}");
    }

    /** @param array{id: string} $params */
    public function delete(array $params): void
    {
        $ctx = AppContext::current();
        $eventId = $params['id'];
        $ctx->requireSignIn("/events/{$eventId}");
        $this->requireCsrf("/events/{$eventId}");

        try {
            // No cascade delete of that event's bookings/activity rows - the reference app's own
            // useDeleteEvent (src/hooks/useEvents.ts) is a bare document delete with no such
            // cleanup either; matched here for parity rather than silently adding scope the
            // reference doesn't have.
            $ctx->mudbase->deleteDocument($ctx->eventsCollectionId, $eventId);
        } catch (MudbaseApiError $e) {
            $this->flashWriteError($e, 'delete this event');
            Response::redirect("/events/{$eventId}");
        }

        Flash::set('success', 'Event deleted.');
        Response::redirect('/');
    }

    /** @param array{id: string} $params */
    public function checkinForm(array $params): void
    {
        $ctx = AppContext::current();
        $eventId = $params['id'];
        $ctx->requireSignIn("/events/{$eventId}/checkin");

        try {
            $event = $ctx->mudbase->getDocument($ctx->eventsCollectionId, $eventId);
        } catch (MudbaseApiError $e) {
            Flash::set('error', $e->isNotFound() ? 'That event no longer exists.' : "Couldn't load that event: {$e->getMessage()}");
            Response::redirect('/');
        }

        View::render('events/checkin', ['event' => $event]);
    }

    /**
     * Looks up a booking by its scanned/pasted qrToken within one event and, if eligible, checks
     * it in — a line-for-line port of the reference app's `useCheckIn` (src/hooks/useBookings.ts).
     * Every outcome is delivered as a flash message on the redirect back to the same page (see
     * Http/Flash.php docblock) rather than introducing a second render-without-redirect path.
     *
     * @param array{id: string} $params
     */
    public function checkin(array $params): void
    {
        $ctx = AppContext::current();
        $eventId = $params['id'];
        $ctx->requireSignIn("/events/{$eventId}/checkin");
        $this->requireCsrf("/events/{$eventId}/checkin");

        $qrToken = trim((string) ($_POST['qrToken'] ?? ''));
        if ($qrToken === '') {
            Flash::set('error', 'Paste or type the scanned code.');
            Response::redirect("/events/{$eventId}/checkin");
        }

        try {
            $result = $ctx->mudbase->listDocuments(
                $ctx->bookingsCollectionId,
                ['eventId' => $eventId, 'qrToken' => $qrToken],
                '-createdAt',
                1,
                1,
            );
            $booking = $result['data'][0] ?? null;

            if ($booking === null) {
                Flash::set('error', 'No booking found for this code at this event.');
                Response::redirect("/events/{$eventId}/checkin");
            }

            $status = (string) ($booking['status'] ?? '');
            $guestName = is_string($booking['userName'] ?? null) ? $booking['userName'] : 'Guest';

            if ($status === 'checked_in') {
                Flash::set('warning', "{$guestName} was already checked in.");
                Response::redirect("/events/{$eventId}/checkin");
            }
            if ($status === 'cancelled') {
                Flash::set('error', 'This booking was cancelled.');
                Response::redirect("/events/{$eventId}/checkin");
            }
            if ($status === 'waitlisted') {
                Flash::set('warning', "{$guestName} is on the waitlist, not confirmed — cannot check in.");
                Response::redirect("/events/{$eventId}/checkin");
            }

            // "confirmed" - the only remaining state - proceeds to check-in. The activity row
            // deliberately logs the booking's own userId/userName as the actor (not the
            // organizer's), mirroring the reference app's useCheckIn exactly: the person being
            // checked in is the subject of "{name} checked in", even though the organizer's
            // account is the one making this API call.
            $ctx->mudbase->updateDocument($ctx->bookingsCollectionId, (string) $booking['_id'], ['status' => 'checked_in']);
            $ctx->mudbase->createDocument($ctx->activityCollectionId, [
                'eventId' => $eventId,
                'actorId' => (string) ($booking['userId'] ?? ''),
                'actorName' => $guestName,
                'action' => 'checked_in',
            ]);
            Flash::set('success', "{$guestName} is checked in.");
        } catch (MudbaseApiError $e) {
            $this->flashWriteError($e, 'check guests in');
        }

        Response::redirect("/events/{$eventId}/checkin");
    }

    /**
     * @return array{0: array<string, mixed>, 1: string|null} [fields, validationErrorMessage]
     */
    private function readAndValidateForm(): array
    {
        $title = trim((string) ($_POST['title'] ?? ''));
        $description = trim((string) ($_POST['description'] ?? ''));
        $startsAtLocal = trim((string) ($_POST['startsAt'] ?? ''));
        $location = trim((string) ($_POST['location'] ?? ''));
        $capacityRaw = trim((string) ($_POST['capacity'] ?? ''));

        if ($title === '') {
            return [[], 'Title is required.'];
        }
        if (mb_strlen($title) > self::MAX_TITLE_LENGTH) {
            return [[], 'Keep the title under ' . self::MAX_TITLE_LENGTH . ' characters.'];
        }
        if (mb_strlen($description) > self::MAX_DESCRIPTION_LENGTH) {
            return [[], 'Keep the description under ' . self::MAX_DESCRIPTION_LENGTH . ' characters.'];
        }
        if ($location === '') {
            return [[], 'Location is required.'];
        }
        if (mb_strlen($location) > self::MAX_LOCATION_LENGTH) {
            return [[], 'Keep the location under ' . self::MAX_LOCATION_LENGTH . ' characters.'];
        }
        if ($startsAtLocal === '') {
            return [[], 'Date and time is required.'];
        }
        $startsAtIso = TimeFormat::fromDateTimeLocal($startsAtLocal);
        if ($startsAtIso === null) {
            return [[], 'Enter a valid date and time.'];
        }
        if (!ctype_digit($capacityRaw)) {
            return [[], 'Capacity must be a whole number.'];
        }
        $capacity = (int) $capacityRaw;
        if ($capacity < self::MIN_CAPACITY) {
            return [[], 'Capacity must be at least 1.'];
        }
        if ($capacity > self::MAX_CAPACITY) {
            return [[], 'Capacity is unrealistically large.'];
        }

        $fields = [
            'title' => $title,
            'startsAt' => $startsAtIso,
            'location' => $location,
            'capacity' => $capacity,
        ];
        // Matches the reference app's `description: values.description || undefined` — an empty
        // description is simply omitted rather than sent as "".
        if ($description !== '') {
            $fields['description'] = $description;
        }

        return [$fields, null];
    }

    private function confirmedCount(AppContext $ctx, string $eventId): int
    {
        try {
            $result = $ctx->mudbase->listDocuments(
                $ctx->bookingsCollectionId,
                ['eventId' => $eventId, 'status' => 'confirmed'],
                '-createdAt',
                1,
                1,
            );
            return $result['pagination']['total'];
        } catch (MudbaseApiError) {
            return 0;
        }
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
