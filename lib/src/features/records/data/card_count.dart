import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads how many cards the signed-in account has.
typedef CardCountLoader = Future<int> Function();

/// The server's count of the account's cards; `null` runs without it.
final cardCountLoaderProvider = Provider<CardCountLoader?>((ref) => null);

/// How many cards the account has, kept for the whole session: null until
/// it is known. 기록하기 reads it to tell a member's first record from the
/// ones after it. It loads once after sign-in and again when a card is
/// saved, claimed or deleted.
final cardCountProvider = NotifierProvider<CardCountNotifier, int?>(
  CardCountNotifier.new,
);

class CardCountNotifier extends Notifier<int?> {
  int _request = 0;

  @override
  int? build() => null;

  /// Reads the count; the one held stays until the new arrives, and when
  /// it does not. Throws what the loader throws. Null without a loader.
  Future<int?> load() async {
    final loader = ref.read(cardCountLoaderProvider);
    if (loader == null) return null;
    final request = ++_request;
    final count = await loader();
    if (request == _request && ref.mounted) state = count;
    return count;
  }

  /// [load] for callers that only want the count kept fresh.
  void refresh() => load().ignore();

  /// Forgets the count of the account that signed out.
  void clear() {
    _request++;
    state = null;
  }
}
