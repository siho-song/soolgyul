/// Counts what happens in the app (a screen opened, a card made) without
/// saying who did it. Nobody waits for a count, and a lost one is dropped.
abstract interface class Analytics {
  /// A screen came to the front.
  void screen(String name);

  /// Something worth counting happened. [details] never name a person, a
  /// drink or anything typed.
  void event(String name, [Map<String, Object> details]);
}

/// Counts nothing: tests, design review and every build that is not the
/// released product.
class NoAnalytics implements Analytics {
  const NoAnalytics();

  @override
  void screen(String name) {}

  @override
  void event(String name, [Map<String, Object> details = const {}]) {}
}
