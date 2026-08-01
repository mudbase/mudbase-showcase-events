<?php
/** @var string $redirectTo */

use App\Http\Csrf;
use App\View;

$title = 'Sign in';

/**
 * Two one-click demo accounts, matching the reference web app's "Sign in as…" quick-fill
 * buttons — but with zero client JavaScript: each is its own real `<form>` with the credentials
 * already baked into hidden inputs, submitting straight to the same /login handler a manually
 * typed form would. See plan/build-plan.md "Stack Decisions".
 */
$demoAccounts = [
    ['label' => 'Sign in as Organizer', 'email' => 'events.organizer.demo@gmail.com'],
    ['label' => 'Sign in as Attendee', 'email' => 'events.attendee.demo@gmail.com'],
];
$demoPassword = 'DemoTest123!';
?>

<div style="max-width:26rem;margin:0 auto">
  <div style="text-align:center;margin-bottom:1.5rem">
    <h1>Sign in</h1>
    <p class="muted">Events, bookings, and check-in are all gated behind a real organizer or attendee account.</p>
  </div>

  <div class="quick-login-row">
    <?php foreach ($demoAccounts as $account): ?>
      <form method="post" action="/login">
        <?= Csrf::field() ?>
        <input type="hidden" name="email" value="<?= View::escape($account['email']) ?>">
        <input type="hidden" name="password" value="<?= View::escape($demoPassword) ?>">
        <input type="hidden" name="redirectTo" value="<?= View::escape($redirectTo) ?>">
        <button type="submit" class="btn btn--outline btn--sm"><?= View::escape($account['label']) ?></button>
      </form>
    <?php endforeach; ?>
  </div>

  <div class="divider-row">or sign in manually</div>

  <form method="post" action="/login">
    <?= Csrf::field() ?>
    <input type="hidden" name="redirectTo" value="<?= View::escape($redirectTo) ?>">
    <div class="field">
      <label for="email">Email</label>
      <input type="email" id="email" name="email" autocomplete="email" required>
    </div>
    <div class="field">
      <label for="password">Password</label>
      <input type="password" id="password" name="password" autocomplete="current-password" required>
    </div>
    <button type="submit" class="btn btn--block">Sign in</button>
  </form>
</div>
