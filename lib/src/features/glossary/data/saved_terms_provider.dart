import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kept_first.dart';
import 'saved_terms.dart';

/// Reads and writes the member's saved terms; `null` leaves every help
/// balloon without its save button (tests and design review).
final savedTermsGatewayProvider = Provider<SavedTermsGateway?>((ref) => null);

/// The signed-in member's saved terms, kept for the session so a balloon
/// knows at once whether its term is saved. A sign-out reloads it (see
/// AppFlow); show it through `shownValue`, which hides the last account's.
final savedTermsProvider =
    AsyncNotifierProvider<SavedTermsNotifier, List<SavedTerm>>(
      SavedTermsNotifier.new,
    );

class SavedTermsNotifier extends KeptFirstNotifier<List<SavedTerm>> {
  /// The phone keeps no copy; the list is asked once a session.
  @override
  Future<List<SavedTerm>?> kept() async => null;

  @override
  Future<List<SavedTerm>> load() async {
    final gateway = ref.read(savedTermsGatewayProvider);
    if (gateway?.accountId == null) return const <SavedTerm>[];
    return gateway!.load();
  }

  /// Saves the term or takes it out; throws when the server did not take it.
  Future<void> setSaved(String key, {required bool saved}) async {
    final gateway = ref.read(savedTermsGatewayProvider)!;
    final account = gateway.accountId;
    final terms = await gateway.setSaved(key, saved: saved);
    if (ref.mounted && gateway.accountId == account) {
      state = AsyncData<List<SavedTerm>>(terms);
    }
  }
}
