import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kept_first.dart';
import 'taste_letters.dart';

/// Reads the reader's letters; `null` shows the design placeholder.
final tasteLettersGatewayProvider = Provider<TasteLettersGateway?>(
  (ref) => null,
);

/// The reader's letters, kept for the session. They change only when a card
/// is saved, claimed or deleted, which reloads them (see AppFlow). On the
/// first load what the phone kept from last time shows until they arrive.
final tasteLettersProvider =
    AsyncNotifierProvider<TasteLettersNotifier, TasteLettersSnapshot>(
      TasteLettersNotifier.new,
    );

class TasteLettersNotifier extends KeptFirstNotifier<TasteLettersSnapshot> {
  @override
  Future<TasteLettersSnapshot?> kept() async =>
      switch (ref.read(tasteLettersGatewayProvider)) {
        final KeepsLast<TasteLettersSnapshot> keeper => keeper.kept(),
        _ => null,
      };

  @override
  Future<TasteLettersSnapshot> load() =>
      ref.read(tasteLettersGatewayProvider)!.load();
}
