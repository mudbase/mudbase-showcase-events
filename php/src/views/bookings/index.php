<?php
/**
 * @var list<array<string, mixed>> $bookings
 * @var array<string, array<string, mixed>> $eventsById
 * @var string|null $error
 */

use App\View;

$title = 'My bookings';
?>

<div style="max-width:38rem;margin:0 auto">
  <h1>My bookings</h1>

  <?php if ($error !== null): ?>
    <p class="flash flash--error"><?= View::escape($error) ?></p>
  <?php elseif ($bookings === []): ?>
    <div class="empty-state">
      <p>You haven't booked any events yet.</p>
    </div>
  <?php else: ?>
    <div class="booking-list">
      <?php foreach ($bookings as $booking): ?>
        <?php $event = $eventsById[(string) ($booking['eventId'] ?? '')] ?? null; ?>
        <?php require __DIR__ . '/../partials/booking_card.php'; ?>
      <?php endforeach; ?>
    </div>
  <?php endif; ?>
</div>
