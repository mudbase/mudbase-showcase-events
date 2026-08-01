<?php
/**
 * Shared create/edit event form, rendered from events/new.php and events/edit.php in the same
 * variable scope. Mirrors the reference app's EventForm.tsx field set and constraints.
 *
 * @var string $formAction
 * @var string $submitLabel
 * @var string|null $errorMessage
 * @var array{title: string, description: string, startsAtLocal: string, location: string, capacity: int|string} $values
 */

use App\Http\Csrf;
use App\View;
?>
<form method="post" action="<?= View::escape($formAction) ?>">
  <?= Csrf::field() ?>

  <?php if ($errorMessage !== null): ?>
    <p class="flash flash--error" role="alert"><?= View::escape($errorMessage) ?></p>
  <?php endif; ?>

  <div class="field">
    <label for="title">Title</label>
    <input type="text" id="title" name="title" maxlength="200" value="<?= View::escape($values['title']) ?>" required>
  </div>

  <div class="field">
    <label for="description">Description</label>
    <textarea id="description" name="description" maxlength="2000" placeholder="Optional"><?= View::escape($values['description']) ?></textarea>
  </div>

  <div class="field-row">
    <div class="field">
      <label for="startsAt">Date &amp; time</label>
      <input type="datetime-local" id="startsAt" name="startsAt" value="<?= View::escape($values['startsAtLocal']) ?>" required>
    </div>
    <div class="field">
      <label for="capacity">Capacity</label>
      <input type="number" id="capacity" name="capacity" min="1" step="1" value="<?= View::escape((string) $values['capacity']) ?>" required>
      <p class="field-hint">Bookings beyond capacity are automatically waitlisted.</p>
    </div>
  </div>

  <div class="field">
    <label for="location">Location</label>
    <input type="text" id="location" name="location" maxlength="200" value="<?= View::escape($values['location']) ?>" required>
  </div>

  <button type="submit" class="btn btn--block"><?= View::escape($submitLabel) ?></button>
</form>
