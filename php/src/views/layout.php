<?php
/**
 * @var \App\Http\AppContext $context
 * @var array{type: string, message: string}|null $flash
 * @var string $content
 * @var string|null $title
 */

use App\Support\Rbac;
use App\View;

$pageTitle = isset($title) && $title !== '' ? "{$title} — Mudbase Events" : 'Mudbase Events';
$role = $context->role();
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?= View::escape($pageTitle) ?></title>
  <link rel="stylesheet" href="/assets/style.css">
</head>
<body>
  <header class="site-header">
    <div class="container site-header__row">
      <a href="/" class="site-header__brand">Mudbase Events</a>
      <nav class="site-header__nav">
        <?php if ($context->isSignedIn()): ?>
          <a class="btn btn--ghost btn--sm" href="/">Events</a>
          <a class="btn btn--ghost btn--sm" href="/bookings">My bookings</a>
          <span class="role-badge role-badge--<?= View::escape($role ?? '') ?>"><?= View::escape(Rbac::roleLabel($role)) ?></span>
          <form method="post" action="/logout" style="display:inline">
            <?= \App\Http\Csrf::field() ?>
            <button type="submit" class="btn btn--outline btn--sm">Sign out</button>
          </form>
        <?php else: ?>
          <a class="btn btn--sm" href="/login">Sign in</a>
        <?php endif; ?>
      </nav>
    </div>
  </header>

  <main class="container">
    <?php if ($flash !== null): ?>
      <div class="flash flash--<?= View::escape($flash['type']) ?>" role="alert">
        <?= View::escape($flash['message']) ?>
      </div>
    <?php endif; ?>

    <?= $content ?>
  </main>

  <footer class="site-footer">
    <div class="container">
      Every event, booking, and activity entry here is served by a real Mudbase project via the
      generated PHP SDK — no custom backend beyond this thin routing/view layer. Role-based
      permissions (organizer/attendee) are enforced by Mudbase's own collection permissions, not
      by this page.
    </div>
  </footer>
</body>
</html>
