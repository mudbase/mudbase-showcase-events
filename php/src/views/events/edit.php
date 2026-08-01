<?php
/**
 * @var array<string, mixed> $event
 * @var string|null $errorMessage
 */

use App\Support\TimeFormat;

$title = 'Edit event';
$eventId = (string) $event['_id'];
$formAction = "/events/{$eventId}/edit";
$submitLabel = 'Save changes';
$values = [
    'title' => (string) ($event['title'] ?? ''),
    'description' => is_string($event['description'] ?? null) ? $event['description'] : '',
    'startsAtLocal' => TimeFormat::toDateTimeLocal(is_string($event['startsAt'] ?? null) ? $event['startsAt'] : null),
    'location' => (string) ($event['location'] ?? ''),
    'capacity' => (int) ($event['capacity'] ?? 1),
];
?>

<div style="max-width:32rem;margin:0 auto">
  <div class="card">
    <h1>Edit event</h1>
    <p class="muted">Changes to capacity are re-checked against existing bookings.</p>
    <?php require __DIR__ . '/../partials/event_form.php'; ?>
  </div>
</div>
