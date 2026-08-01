<?php
/**
 * @var list<array<string, mixed>> $events
 * @var array{page: int, limit: int, total: int, totalPages: int} $pagination
 * @var array<string, int> $confirmedByEventId
 * @var string|null $error
 * @var \App\Http\AppContext $context
 */

use App\Support\Rbac;
use App\View;

$title = null;
$role = $context->role();
?>

<div class="page-header">
  <div>
    <h1 style="margin:0">Upcoming events</h1>
    <p class="muted" style="margin:0.2rem 0 0">Sorted soonest first.</p>
  </div>
  <?php if (Rbac::isOrganizer($role)): ?>
    <a class="btn" href="/events/new">New event</a>
  <?php endif; ?>
</div>

<?php if ($error !== null): ?>
  <p class="flash flash--error"><?= View::escape($error) ?></p>
<?php elseif ($events === []): ?>
  <div class="empty-state">
    <p>No events yet<?= Rbac::isOrganizer($role) ? ' — create the first one above.' : '.' ?></p>
  </div>
<?php else: ?>
  <div class="event-list">
    <?php foreach ($events as $event): ?>
      <?php $confirmed = $confirmedByEventId[(string) $event['_id']] ?? 0; ?>
      <?php require __DIR__ . '/../partials/event_card.php'; ?>
    <?php endforeach; ?>
  </div>

  <?php if ($pagination['totalPages'] > 1): ?>
    <div class="pagination-row">
      <?php if ($pagination['page'] > 1): ?>
        <a class="btn btn--outline btn--sm" href="/?page=<?= $pagination['page'] - 1 ?>">&larr; Newer</a>
      <?php endif; ?>
      <span>Page <?= $pagination['page'] ?> of <?= $pagination['totalPages'] ?></span>
      <?php if ($pagination['page'] < $pagination['totalPages']): ?>
        <a class="btn btn--outline btn--sm" href="/?page=<?= $pagination['page'] + 1 ?>">Later &rarr;</a>
      <?php endif; ?>
    </div>
  <?php endif; ?>
<?php endif; ?>
