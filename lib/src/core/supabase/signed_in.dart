import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in account's id; a gateway that reads the reader's own rows
/// fails with this before it asks.
String signedInUserId(SupabaseClient client) =>
    client.auth.currentUser?.id ?? (throw StateError('로그인이 필요합니다.'));
