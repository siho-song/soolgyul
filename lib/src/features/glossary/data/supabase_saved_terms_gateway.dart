import 'package:supabase_flutter/supabase_flutter.dart';

import 'saved_terms.dart';

/// Reads and writes through the `saved-terms` function, which knows the
/// dictionary the terms are explained by.
class SupabaseSavedTermsGateway implements SavedTermsGateway {
  const SupabaseSavedTermsGateway(this._client);
  final SupabaseClient _client;

  @override
  String? get accountId => _client.auth.currentUser?.id;

  @override
  Future<List<SavedTerm>> load() async {
    final response = await _client.functions.invoke(
      'saved-terms',
      method: HttpMethod.get,
    );
    return savedTermsFromResponse(response.data);
  }

  @override
  Future<List<SavedTerm>> setSaved(String key, {required bool saved}) async {
    final response = await _client.functions.invoke(
      'saved-terms',
      body: <String, dynamic>{'key': key, 'saved': saved},
    );
    return savedTermsFromResponse(response.data);
  }
}

/// The list in a `saved-terms` answer; a row the app cannot read is left out.
List<SavedTerm> savedTermsFromResponse(Object? data) {
  final rows = data is Map ? data['terms'] : null;
  if (rows is! List) throw const FormatException('saved terms expected');
  return <SavedTerm>[for (final row in rows) ?SavedTerm.fromJson(row)];
}
