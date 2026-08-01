<?php

declare(strict_types=1);

namespace App\Http;

use App\Mudbase\MudbaseClient;

/**
 * Per-request registry handed to every controller and view: the authenticated Mudbase client and
 * the current session user (or null) — the server-rendered counterpart of the reference app's
 * React `useMudbase()` context (src/lib/mudbase-provider.tsx). One instance per request; built
 * once in bootstrap.php right after the session handshake.
 */
final class AppContext
{
    private static ?self $instance = null;

    /** @param array<string, mixed>|null $user */
    public function __construct(
        public readonly MudbaseClient $mudbase,
        public readonly ?array $user,
        public readonly string $eventsCollectionId,
        public readonly string $bookingsCollectionId,
        public readonly string $activityCollectionId,
        public readonly string $mudbaseUrl,
    ) {
    }

    public static function set(self $context): void
    {
        self::$instance = $context;
    }

    public static function current(): self
    {
        if (self::$instance === null) {
            throw new \RuntimeException('AppContext accessed before bootstrap set it.');
        }
        return self::$instance;
    }

    public function isSignedIn(): bool
    {
        // `GET /api/auth/local/session` does not reliably return an `isAnonymous` key at all in
        // practice — confirmed against the live API on the sibling social/ecommerce/kanban PHP
        // ports, the key is simply absent from the response body — so a bare
        // `($this->user['isAnonymous'] ?? false) !== true` check treats a missing key as "not
        // anonymous" and would wrongly call it signed in. `customRole` is the reliable signal
        // instead: Mudbase only ever assigns one of this project's role slugs
        // (organizer/attendee) to a real registered account. This app has no anonymous/guest
        // session at all (see plan/build-plan.md "Auth Flow"), so `$this->user` is either a real
        // account or null — but the same defensive check is kept verbatim for consistency with
        // every other PHP port in this showcase family.
        return $this->user !== null
            && ($this->user['isAnonymous'] ?? false) !== true
            && ($this->user['customRole'] ?? null) !== null;
    }

    /**
     * Redirects an unauthenticated visitor to `/login`, carrying the originally-requested path
     * back through `?redirect=` so they land where they meant to go after signing in. Every
     * controller other than AuthController calls this first — there is no anonymous/guest mode in
     * this app for either role (see plan/build-plan.md "Auth Flow").
     */
    public function requireSignIn(string $requestedPath): void
    {
        if (!$this->isSignedIn()) {
            Response::redirect('/login?redirect=' . urlencode($requestedPath));
        }
    }

    public function userId(): ?string
    {
        $id = $this->user['id'] ?? $this->user['_id'] ?? null;
        return is_string($id) ? $id : null;
    }

    /** One of "organizer"/"attendee", or null if not signed in / role unset. */
    public function role(): ?string
    {
        $role = $this->user['customRole'] ?? null;
        return is_string($role) && $role !== '' ? $role : null;
    }

    /** `"{firstName} {lastName}"`, trimmed — the denormalized organizer/attendee name every write stores. */
    public function displayName(): ?string
    {
        if ($this->user === null) {
            return null;
        }
        $first = is_string($this->user['firstName'] ?? null) ? $this->user['firstName'] : '';
        $last = is_string($this->user['lastName'] ?? null) ? $this->user['lastName'] : '';
        $name = trim("{$first} {$last}");
        return $name !== '' ? $name : null;
    }
}
