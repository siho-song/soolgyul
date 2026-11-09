import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'next_drink_guides.dart';
import 'taste_letters.dart';

/// Reads the reader's letters; `null` shows the design placeholder.
final tasteLettersGatewayProvider = Provider<TasteLettersGateway?>(
  (ref) => null,
);

/// Reads the guides of the reader's recent cards; `null` shows the fixture.
final nextDrinkGuidesGatewayProvider = Provider<NextDrinkGuidesGateway?>(
  (ref) => null,
);

/// The reader's letters, kept for the session. They change only when a card
/// is saved, claimed or deleted, which reloads them (see AppFlow).
final tasteLettersProvider = FutureProvider<TasteLettersSnapshot>(
  (ref) => ref.watch(tasteLettersGatewayProvider)!.load(),
);

/// The guides of the reader's recent cards, kept like [tasteLettersProvider].
final nextDrinkGuidesProvider = FutureProvider<List<NextDrinkGuide>>(
  (ref) => ref.watch(nextDrinkGuidesGatewayProvider)!.load(),
);
