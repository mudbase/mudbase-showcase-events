<?php
/**
 * Rendered once per event from events/index.php, in the same variable scope.
 *
 * @var array<string, mixed> $event
 * @var int $confirmed
 */

use App\Support\CapacityPresentation;
use App\Support\TimeFormat;
use App\View;

$eventId = (string) $event['_id'];
$title = (string) ($event['title'] ?? '');
$location = (string) ($event['location'] ?? '');
$organizerName = (string) ($event['organizerName'] ?? '');
$capacity = (int) ($event['capacity'] ?? 0);
$badge = CapacityPresentation::describe($confirmed, $capacity);
?>
<a class="event-card" href="/events/<?= urlencode($eventId) ?>">
  <div class="card event-card__inner">
    <div class="event-card__header">
      <div>
        <h3 class="event-card__title"><?= View::escape($title) ?></h3>
        <p class="muted" style="margin:0.2rem 0 0;font-size:0.8rem">Hosted by <?= View::escape($organizerName) ?></p>
      </div>
      <span class="capacity-badge <?= View::escape($badge['cssClass']) ?>"><?= View::escape($badge['label']) ?></span>
    </div>
    <div class="event-card__meta">
      <div class="event-card__meta-row">📅 <?= View::escape(TimeFormat::dateTime((string) ($event['startsAt'] ?? ''))) ?></div>
      <div class="event-card__meta-row">📍 <?= View::escape($location) ?></div>
    </div>
  </div>
</a>
