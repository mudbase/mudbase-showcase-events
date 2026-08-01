<?php
/** @var array<string, mixed> $event */

use App\Http\Csrf;
use App\View;

$eventId = (string) $event['_id'];
$title = 'Check in — ' . (string) ($event['title'] ?? '');
?>

<div style="max-width:30rem;margin:0 auto">
  <div class="card">
    <h1>Check in — <?= View::escape((string) ($event['title'] ?? '')) ?></h1>
    <p class="muted">Paste or type the guest's scanned QR code to check them in.</p>

    <form method="post" action="/events/<?= urlencode($eventId) ?>/checkin" class="checkin-form">
      <?= Csrf::field() ?>
      <div class="field">
        <label for="qrToken">Scanned / pasted code</label>
        <input type="text" id="qrToken" name="qrToken" placeholder="e.g. 9f2c1a4b…" autofocus required>
      </div>
      <button type="submit" class="btn">Check in</button>
    </form>
  </div>
</div>
