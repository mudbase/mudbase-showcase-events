import 'package:mudbase_showcase_events/core/formatters.dart';
import 'package:test/test.dart';

void main() {
  group('formatRelativeTime', () {
    test('returns "just now" for under 5 seconds', () {
      final now = DateTime.now().subtract(const Duration(seconds: 2));
      expect(formatRelativeTime(now), 'just now');
    });

    test('returns seconds for under a minute', () {
      final then = DateTime.now().subtract(const Duration(seconds: 30));
      expect(formatRelativeTime(then), endsWith('s'));
    });

    test('returns minutes for under an hour', () {
      final then = DateTime.now().subtract(const Duration(minutes: 5));
      expect(formatRelativeTime(then), endsWith('m'));
    });

    test('returns hours for under a day', () {
      final then = DateTime.now().subtract(const Duration(hours: 3));
      expect(formatRelativeTime(then), endsWith('h'));
    });

    test('returns days for under a week', () {
      final then = DateTime.now().subtract(const Duration(days: 3));
      expect(formatRelativeTime(then), endsWith('d'));
    });

    test('falls back to a formatted date past a week', () {
      final then = DateTime.now().subtract(const Duration(days: 30));
      final result = formatRelativeTime(then);
      expect(result, isNot(endsWith('d')));
      expect(result, isNot(endsWith('h')));
      expect(result, isNot(endsWith('m')));
      expect(result, isNot(endsWith('s')));
    });
  });

  group('formatDateTime', () {
    test('includes both a date and a time component', () {
      final result = formatDateTime(DateTime(2026, 9, 1, 18, 30));
      expect(result, contains('2026'));
      expect(result, contains(','));
    });
  });

  group('generateQrToken', () {
    test('produces a 32-character lowercase hex string', () {
      final token = generateQrToken();
      expect(token.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(token), isTrue);
    });

    test('is different on every call', () {
      final tokens = List.generate(20, (_) => generateQrToken());
      expect(tokens.toSet().length, tokens.length);
    });
  });
}
