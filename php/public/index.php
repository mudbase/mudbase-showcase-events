<?php

declare(strict_types=1);

require dirname(__DIR__) . '/src/bootstrap.php';

use App\Controllers\AuthController;
use App\Controllers\BookingController;
use App\Controllers\EventController;
use App\Mudbase\MudbaseApiError;
use App\Router;
use App\View;

$router = new Router();

$events = new EventController();
$bookings = new BookingController();
$auth = new AuthController();

$router->get('/', [$events, 'index']);
$router->get('/events/new', [$events, 'newForm']);
$router->post('/events', [$events, 'create']);
$router->get('/events/{id}', [$events, 'show']);
$router->get('/events/{id}/edit', [$events, 'editForm']);
$router->post('/events/{id}/edit', [$events, 'update']);
$router->post('/events/{id}/delete', [$events, 'delete']);
$router->get('/events/{id}/checkin', [$events, 'checkinForm']);
$router->post('/events/{id}/checkin', [$events, 'checkin']);

$router->get('/bookings', [$bookings, 'index']);
$router->post('/bookings', [$bookings, 'create']);
$router->post('/bookings/{id}/cancel', [$bookings, 'cancel']);

$router->get('/login', [$auth, 'loginForm']);
$router->post('/login', [$auth, 'login']);
$router->post('/logout', [$auth, 'logout']);

try {
    $router->dispatch((string) $_SERVER['REQUEST_METHOD'], (string) $_SERVER['REQUEST_URI'], function (): void {
        View::render('errors/not_found', [], 404);
    });
} catch (MudbaseApiError $e) {
    if ($e->isUnauthorized()) {
        // Token expired/was revoked mid-session - clear it and send the visitor back to /login.
        // This app has no guest mode at all, so there is nowhere degraded to fall back to.
        $requestedPath = (string) $_SERVER['REQUEST_URI'];
        unset($_SESSION['mudbase_token'], $_SESSION['mudbase_refresh_token'], $_SESSION['mudbase_user']);
        header('Location: /login?redirect=' . urlencode($requestedPath));
        exit;
    }

    View::render('errors/server_error', ['message' => $e->getMessage()], 500);
} catch (\Throwable $e) {
    View::render('errors/server_error', ['message' => $e->getMessage()], 500);
}
