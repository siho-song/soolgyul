import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in account's id; a gateway that reads the reader's own rows
/// fails with this before it asks.
String signedInUserId(SupabaseClient client) =>
    client.auth.currentUser?.id ?? (throw StateError('no signed-in user'));

/// Asks for the signed-in account's own rows. The answer is given only when
/// the same account is still signed in as it arrives, so one account's rows
/// are never shown to the next.
Future<T> askAsSignedIn<T>(
  SupabaseClient client,
  Future<T> Function(String userId) ask,
) async {
  final userId = signedInUserId(client);
  final answer = await ask(userId);
  if (client.auth.currentUser?.id != userId) {
    throw StateError('the signed-in account changed');
  }
  return answer;
}
