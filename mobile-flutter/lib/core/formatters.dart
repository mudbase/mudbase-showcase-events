import 'dart:math';

import 'package:intl/intl.dart';

/// Relative + absolute timestamp formatting for the activity feed and event
/// detail screen, plus the check-in QR token generator. Ported directly from
/// the reference web app's `src/lib/utils.ts` (same threshold values).

/// Mirrors `formatRelativeTime` in `web/src/lib/utils.ts` exactly (`"just
/// now"` under 5s, then `"Ns"`/`"Nm"`/`"Nh"`/`"Nd"`, falling back to a plain
/// medium-style date past a week).
String formatRelativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final diffSeconds = now.difference(dateTime).inSeconds;

  if (diffSeconds < 5) return 'just now';
  if (diffSeconds < 60) return '${diffSeconds}s';
  final diffMinutes = now.difference(dateTime).inMinutes;
  if (diffMinutes < 60) return '${diffMinutes}m';
  final diffHours = now.difference(dateTime).inHours;
  if (diffHours < 24) return '${diffHours}h';
  final diffDays = now.difference(dateTime).inDays;
  if (diffDays < 7) return '${diffDays}d';
  return DateFormat.yMMMd().format(dateTime);
}

/// Mirrors `formatDateTime` in `web/src/lib/utils.ts` (medium date + short
/// time) - used on the event detail screen and booking cards.
String formatDateTime(DateTime dateTime) {
  return '${DateFormat.yMMMd().format(dateTime)}, ${DateFormat.jm().format(dateTime)}';
}

/// Random token generator used as the seed for `Random.secure()` calls below
/// so every invocation draws fresh entropy rather than sharing one instance
/// across the process lifetime unnecessarily (each call already constructs
/// its own `Random.secure()`, this constant only documents the byte count
/// chosen).
const int _qrTokenByteCount = 16;

/// A random, unguessable single-use check-in code. Not a security credential
/// in the cryptographic sense (this is a demo ticketing app, not a payments
/// system) - mirrors the web app's `generateQrToken()`
/// (`crypto.randomUUID().replace(/-/g, "")`, 122 bits of entropy) with a Dart
/// equivalent: 16 cryptographically-random bytes (128 bits) hex-encoded,
/// using `Random.secure()` (a CSPRNG, not the default `Random()`) since this
/// value must not be guessable by another attendee.
String generateQrToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(
    _qrTokenByteCount,
    (_) => random.nextInt(256),
  );
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
