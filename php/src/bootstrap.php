<?php

declare(strict_types=1);

use App\Config;
use App\Http\AppContext;
use App\Mudbase\MudbaseClient;

require dirname(__DIR__) . '/vendor/autoload.php';

$rootDir = dirname(__DIR__);
Config::load($rootDir);

session_name(Config::optional('SESSION_NAME', 'mudbase_showcase_events_php'));
session_start();

$mudbaseUrl = rtrim(Config::optional('MUDBASE_URL', 'https://cloud.mudbase.dev'), '/');
$projectId = Config::required('MUDBASE_PROJECT_ID');
$eventsCollectionId = Config::required('MUDBASE_EVENTS_COLLECTION_ID');
$bookingsCollectionId = Config::required('MUDBASE_BOOKINGS_COLLECTION_ID');
$activityCollectionId = Config::required('MUDBASE_ACTIVITY_COLLECTION_ID');

// Unlike some sibling PHP ports, this app never establishes an anonymous/guest session — every
// one of the two roles (organizer/attendee) requires a real login (see plan/build-plan.md "Auth
// Flow"). If there's no token in $_SESSION yet, the request simply boots with $user = null; every
// controller other than AuthController calls AppContext::requireSignIn() before rendering
// anything, which redirects to /login.
$token = $_SESSION['mudbase_token'] ?? null;
$refreshToken = $_SESSION['mudbase_refresh_token'] ?? null;

/**
 * Wired into MudbaseClient so a mid-request 401 (access token expired) can be recovered from
 * silently: MudbaseClient::callApi()/listDocuments() exchange the refresh token for a new pair
 * via POST /api/auth/refresh and retry the failing call once before giving up. This callback is
 * the only thing that persists the refreshed pair back into $_SESSION — MudbaseClient itself has
 * no session dependency, so it stays usable from a CLI script. Only a refresh-token failure
 * (itself expired/revoked) still reaches the front controller's catch(MudbaseApiError) in
 * public/index.php, which clears the session and redirects to /login — see that file.
 */
$onTokenRefreshed = static function (string $newToken, ?string $newRefreshToken): void {
    $_SESSION['mudbase_token'] = $newToken;
    $_SESSION['mudbase_refresh_token'] = $newRefreshToken;
};

$mudbase = new MudbaseClient(
    $mudbaseUrl,
    $projectId,
    is_string($token) ? $token : null,
    is_string($refreshToken) ? $refreshToken : null,
    $onTokenRefreshed,
);
$user = is_array($_SESSION['mudbase_user'] ?? null) ? $_SESSION['mudbase_user'] : null;

AppContext::set(new AppContext(
    mudbase: $mudbase,
    user: $user,
    eventsCollectionId: $eventsCollectionId,
    bookingsCollectionId: $bookingsCollectionId,
    activityCollectionId: $activityCollectionId,
    mudbaseUrl: $mudbaseUrl,
));
