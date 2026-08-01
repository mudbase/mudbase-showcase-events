<?php
/**
 * @var array<string, mixed> $event
 * @var int $confirmed
 * @var array<string, mixed>|null $myBooking
 * @var list<array<string, mixed>> $activity
 * @var string|null $activityError
 * @var \App\Http\AppContext $context
 */

use App\Http\Csrf;
use App\Support\ActivityText;
use App\Support\CapacityPresentation;
use App\Support\Rbac;
use App\Support\TimeFormat;
use App\View;

$title = (string) ($event['title'] ?? '');
$eventId = (string) $event['_id'];
$capacity = (int) ($event['capacity'] ?? 0);
$organizerId = (string) ($event['organizerId'] ?? '');
$description = is_string($event['description'] ?? null) ? $event['description'] : '';
$role = $context->role();
$userId = $context->userId();
$isOwner = Rbac::canManageOwnEvent($role, $organizerId, $userId);
$badge = CapacityPresentation::describe($confirmed, $capacity);

$statusLabels = [
    'confirmed' => "You're booked",
    'waitlisted' => "You're on the waitlist",
    'checked_in' => "You're checked in",
];
?>

<div style="max-width:38rem;margin:0 auto">
  <div class="event-detail__header">
    <h1 style="margin:0"><?= View::escape($title) ?></h1>
    <span class="capacity-badge <?= View::escape($badge['cssClass']) ?>"><?= View::escape($badge['label']) ?></span>
  </div>
  <p class="muted">Hosted by <?= View::escape((string) ($event['organizerName'] ?? '')) ?></p>

  <div class="event-detail__meta">
    <div class="event-detail__meta-row">📅 <?= View::escape(TimeFormat::dateTime((string) ($event['startsAt'] ?? ''))) ?></div>
    <div class="event-detail__meta-row">📍 <?= View::escape((string) ($event['location'] ?? '')) ?></div>
    <div class="event-detail__meta-row">👥 Capacity: <?= $capacity ?></div>
  </div>

  <?php if ($description !== ''): ?>
    <p class="event-detail__description"><?= View::escape($description) ?></p>
  <?php endif; ?>

  <div class="book-panel">
    <?php if (!$isOwner): ?>
      <?php if ($myBooking !== null): ?>
        <span class="status-badge status-badge--<?= View::escape((string) $myBooking['status']) ?>">
          <?= View::escape($statusLabels[(string) $myBooking['status']] ?? 'Booking on file') ?>
        </span>
        <a class="btn btn--outline btn--sm" href="/bookings">View my bookings</a>
      <?php else: ?>
        <form method="post" action="/bookings">
          <?= Csrf::field() ?>
          <input type="hidden" name="eventId" value="<?= View::escape($eventId) ?>">
          <button type="submit" class="btn">Book this event</button>
        </form>
      <?php endif; ?>
    <?php endif; ?>
  </div>

  <?php if ($isOwner): ?>
    <div class="organizer-actions">
      <span class="organizer-actions__label">Organizer</span>
      <a class="btn btn--outline btn--sm" href="/events/<?= urlencode($eventId) ?>/edit">Edit</a>
      <a class="btn btn--outline btn--sm" href="/events/<?= urlencode($eventId) ?>/checkin">Check-in</a>
      <details class="inline-confirm">
        <summary class="btn btn--destructive btn--sm">Delete</summary>
        <div class="confirm-panel">
          <span class="muted" style="font-size:0.85rem">Delete this event permanently?</span>
          <form method="post" action="/events/<?= urlencode($eventId) ?>/delete">
            <?= Csrf::field() ?>
            <button type="submit" class="btn btn--destructive btn--sm">Confirm delete</button>
          </form>
        </div>
      </details>
    </div>
  <?php endif; ?>

  <hr class="separator">

  <h2>Activity</h2>
  <?php if ($activityError !== null): ?>
    <p class="flash flash--error"><?= View::escape($activityError) ?></p>
  <?php elseif ($activity === []): ?>
    <p class="muted">No activity yet.</p>
  <?php else: ?>
    <ul class="activity-list">
      <?php foreach ($activity as $entry): ?>
        <li class="activity-item">
          <span><?= View::escape(ActivityText::describe($entry)) ?></span>
          <span class="activity-item__time"><?= View::escape(TimeFormat::relative(is_string($entry['createdAt'] ?? null) ? $entry['createdAt'] : null)) ?></span>
        </li>
      <?php endforeach; ?>
    </ul>
  <?php endif; ?>
</div>
