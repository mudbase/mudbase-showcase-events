/// Compile-time configuration, supplied via `--dart-define` /
/// `--dart-define-from-file` - this project's Flutter convention (see
/// `flutter/SKILL.md` and the sibling `mudbase-showcase-kanban` port), never
/// a runtime `.env` file.
///
/// Every value below is public (a Mudbase project/collection id is not a
/// secret, same as the web app's `NEXT_PUBLIC_*` vars) - there is no
/// server-side credential anywhere in this app. This app targets one
/// specific, already-provisioned, real shared project, so every value below
/// defaults to that project's real ids, matching the reference web app's own
/// `.env.example` (which ships the real values pre-filled, ready to run).
/// `--dart-define` still overrides any of them if a consumer of this repo
/// points it at their own project.
class EnvConfig {
  const EnvConfig._();

  static const String mudbaseBaseUrl = String.fromEnvironment(
    'MUDBASE_BASE_URL',
    defaultValue: 'https://cloud.mudbase.dev',
  );

  static const String mudbaseProjectId = String.fromEnvironment(
    'MUDBASE_PROJECT_ID',
    defaultValue: '6a6d3fa9d07caabbbdfc564f',
  );

  static const String eventsCollectionId = String.fromEnvironment(
    'EVENTS_COLLECTION_ID',
    defaultValue: '6a6d3fcad07caabbbdfc5802',
  );

  static const String bookingsCollectionId = String.fromEnvironment(
    'BOOKINGS_COLLECTION_ID',
    defaultValue: '6a6d3fcbd07caabbbdfc5819',
  );

  static const String activityCollectionId = String.fromEnvironment(
    'ACTIVITY_COLLECTION_ID',
    defaultValue: '6a6d3fccd07caabbbdfc582e',
  );

  /// Fails fast at startup (in `main()`) rather than surfacing a confusing
  /// mid-flow 404/401 the first time a screen tries to read an empty
  /// collection id - mirrors the web app's `requireEnv()`
  /// (`web/src/lib/config.ts`) and the sibling kanban Flutter port's own
  /// `assertConfigured()`. In practice this only fires if a consumer
  /// explicitly overrides one of the defaults above with an empty string.
  static void assertConfigured() {
    final missing = <String>[
      if (mudbaseProjectId.isEmpty) 'MUDBASE_PROJECT_ID',
      if (eventsCollectionId.isEmpty) 'EVENTS_COLLECTION_ID',
      if (bookingsCollectionId.isEmpty) 'BOOKINGS_COLLECTION_ID',
      if (activityCollectionId.isEmpty) 'ACTIVITY_COLLECTION_ID',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required --dart-define values: ${missing.join(', ')}. '
        'See README "Setup" for the full list and how to supply them.',
      );
    }
  }
}
