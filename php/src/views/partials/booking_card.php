<?php
/**
 * Rendered once per booking from bookings/index.php, in the same variable scope.
 *
 * @var array<string, mixed> $booking
 * @var array<string, mixed>|null $event
 */

use App\Http\Csrf;
use App\Support\TimeFormat;
use App\View;

$bookingId = (string) $booking['_id'];
$status = (string) ($booking['status'] ?? '');
$qrToken = (string) ($booking['qrToken'] ?? '');
$canCancel = $status === 'confirmed' || $status === 'waitlisted';

$statusLabels = [
    'confirmed' => 'Confirmed',
    'waitlisted' => 'Waitlisted',
    'checked_in' => 'Checked in',
    'cancelled' => 'Cancelled',
];
?>
<div class="card">
  <div class="booking-card__header">
    <div>
      <h3 class="booking-card__title">
        <?php if ($event !== null): ?>
          <a href="/events/<?= urlencode((string) $event['_id']) ?>"><?= View::escape((string) ($event['title'] ?? '')) ?></a>
        <?php else: ?>
          Event unavailable
        <?php endif; ?>
      </h3>
      <?php if ($event !== null): ?>
        <div class="booking-card__meta">
          <span>📅 <?= View::escape(TimeFormat::dateTime((string) ($event['startsAt'] ?? ''))) ?></span>
          <span>📍 <?= View::escape((string) ($event['location'] ?? '')) ?></span>
        </div>
      <?php endif; ?>
    </div>
    <span class="status-badge status-badge--<?= View::escape($status) ?>"><?= View::escape($statusLabels[$status] ?? $status) ?></span>
  </div>

  <div class="booking-card__body">
    <?php if ($status !== 'cancelled'): ?>
      <div class="booking-card__qr">
        <img
          src="https://api.qrserver.com/v1/create-qr-code/?size=90x90&data=<?= urlencode($qrToken) ?>"
          width="90" height="90" alt="QR code for this booking's check-in token" loading="lazy">
        <span class="booking-card__qr-token"><?= View::escape($qrToken) ?></span>
      </div>
    <?php else: ?>
      <p class="muted" style="margin:0">This booking was cancelled.</p>
    <?php endif; ?>

    <?php if ($canCancel): ?>
      <form method="post" action="/bookings/<?= urlencode($bookingId) ?>/cancel">
        <?= Csrf::field() ?>
        <button type="submit" class="btn btn--outline btn--sm">Cancel</button>
      </form>
    <?php endif; ?>
  </div>
</div>
