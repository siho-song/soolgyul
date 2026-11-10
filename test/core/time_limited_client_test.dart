import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/core/supabase/time_limited_client.dart';

/// Answers after [delay]; never, when [delay] is null.
TimeLimitedClient _client({Duration? delay}) => TimeLimitedClient(
  inner: MockClient((request) async {
    if (delay == null) return Completer<http.Response>().future;
    await Future<void>.delayed(delay);
    return http.Response('{}', 200);
  }),
  readLimit: const Duration(milliseconds: 20),
  limit: const Duration(milliseconds: 150),
  uploadLimit: const Duration(milliseconds: 600),
);

void main() {
  final read = Uri.parse('https://example.test/rest/v1/taste_letters');
  final call = Uri.parse('https://example.test/rest/v1/rpc/any');
  final photo = Uri.parse(
    'https://example.test/storage/v1/object/bucket/photo.jpg',
  );

  test('a request nobody answers ends at its limit', () async {
    final client = _client();

    await expectLater(client.get(read), throwsA(isA<TimeoutException>()));
    await expectLater(client.post(call), throwsA(isA<TimeoutException>()));
    await expectLater(client.post(photo), throwsA(isA<TimeoutException>()));
  });

  test('a call waits longer than a read, an upload longer still', () async {
    final slow = _client(delay: const Duration(milliseconds: 60));
    await expectLater(slow.get(read), throwsA(isA<TimeoutException>()));
    expect((await slow.post(call)).statusCode, 200);

    final slower = _client(delay: const Duration(milliseconds: 300));
    await expectLater(slower.post(call), throwsA(isA<TimeoutException>()));
    expect((await slower.post(photo)).statusCode, 200);
  });
}
