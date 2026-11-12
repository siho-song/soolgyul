import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A Supabase client that reaches no server: signing in always succeeds as
/// [userId], and every other request is answered by [respond].
SupabaseClient fakeSupabaseClient(
  Future<http.Response> Function(http.Request request) respond, {
  String userId = 'user-1',
}) => SupabaseClient(
  'https://example.supabase.co',
  'test-key',
  httpClient: MockClient((request) async {
    if (request.url.path.contains('/auth/')) {
      return http.Response(
        jsonEncode({
          'access_token': 'test-token',
          'refresh_token': 'test-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': userId,
            'aud': 'authenticated',
            'created_at': '2026-09-01T00:00:00Z',
            'app_metadata': <String, dynamic>{},
            'user_metadata': <String, dynamic>{},
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return respond(request);
  }),
);

/// Signs the fake client in, as the tests of an owner's gateway need.
Future<void> signInFake(SupabaseClient client) => client.auth
    .signInWithPassword(email: 'test@example.com', password: 'test-password');
