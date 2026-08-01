<?php
/** @var string|null $errorMessage */

$title = 'New event';
$formAction = '/events';
$submitLabel = 'Create event';
$values = ['title' => '', 'description' => '', 'startsAtLocal' => '', 'location' => '', 'capacity' => 20];
?>

<div style="max-width:32rem;margin:0 auto">
  <div class="card">
    <h1>New event</h1>
    <p class="muted">Set a capacity — bookings beyond it are automatically waitlisted.</p>
    <?php require __DIR__ . '/../partials/event_form.php'; ?>
  </div>
</div>
