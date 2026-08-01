<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Http\AppContext;
use App\Http\Csrf;
use App\Http\Flash;
use App\Http\Response;
use App\Mudbase\MudbaseApiError;
use App\View;

/**
 * Login/logout — mirrors the reference app's `/login` and `useAuth()`. No registration UI: the
 * task's two demo accounts (organizer/attendee) already exist on the live project, so this app
 * only ever signs in, never signs up (see plan/build-plan.md "Auth Flow").
 */
final class AuthController
{
    /** @param array<string, string> $params */
    public function loginForm(array $params): void
    {
        $ctx = AppContext::current();
        if ($ctx->isSignedIn()) {
            Response::redirect('/');
        }
        View::render('login', ['redirectTo' => (string) ($_GET['redirect'] ?? '/')]);
    }

    /** @param array<string, string> $params */
    public function login(array $params): void
    {
        $ctx = AppContext::current();
        $this->requireCsrf('/login');

        $email = trim((string) ($_POST['email'] ?? ''));
        $password = (string) ($_POST['password'] ?? '');
        $redirectTo = (string) ($_POST['redirectTo'] ?? '/');

        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || $password === '') {
            Flash::set('error', 'Enter a valid email address and password.');
            Response::redirect('/login');
        }

        try {
            $session = $ctx->mudbase->login($email, $password);
        } catch (MudbaseApiError $e) {
            Flash::set('error', $e->getMessage());
            Response::redirect('/login');
        }

        // Regenerate the session id on every privilege change (no session -> real account) so a
        // session identifier issued before authentication can never be reused to ride along with
        // the authenticated one.
        session_regenerate_id(true);

        $_SESSION['mudbase_token'] = $session['token'];
        $_SESSION['mudbase_refresh_token'] = $session['refreshToken'];
        $_SESSION['mudbase_user'] = $session['user'];

        // redirectTo travels here from an unauthenticated visit that was bounced to
        // /login?redirect=... - validate it as a same-site path before trusting it, same guard
        // Response::redirectToSafe uses everywhere else.
        Response::redirectToSafe($redirectTo, '/');
    }

    /** @param array<string, string> $params */
    public function logout(array $params): void
    {
        $ctx = AppContext::current();
        $this->requireCsrf('/');

        $ctx->mudbase->logout();
        unset($_SESSION['mudbase_token'], $_SESSION['mudbase_refresh_token'], $_SESSION['mudbase_user']);
        session_regenerate_id(true);

        Response::redirect('/login');
    }

    private function requireCsrf(string $fallbackRedirect): void
    {
        if (!Csrf::verify($_POST['_csrf'] ?? null)) {
            Flash::set('error', 'Your session expired — please try again.');
            Response::redirect($fallbackRedirect);
        }
    }
}
