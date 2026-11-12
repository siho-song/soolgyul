import 'dart:async';

import 'package:fake_async/fake_async.dart';
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

  test('a request nobody answers ends at its limit', () {
    fakeAsync((async) {
      final client = _client();
      final timeouts = <Object>[];
      for (final request in [
        client.get(read),
        client.post(call),
        client.post(photo),
      ]) {
        request.then((_) {}, onError: timeouts.add);
      }

      async.elapse(const Duration(milliseconds: 600));
      async.flushMicrotasks();
      expect(timeouts, everyElement(isA<TimeoutException>()));
      expect(timeouts, hasLength(3));
    });
  });

  test('a call waits longer than a read, an upload longer still', () {
    fakeAsync((async) {
      final slow = _client(delay: const Duration(milliseconds: 60));
      Object? readError;
      slow
          .get(read)
          .then(
            (_) {},
            onError: (Object e) {
              readError = e;
            },
          );
      int? callStatus;
      slow.post(call).then((response) => callStatus = response.statusCode);

      final slower = _client(delay: const Duration(milliseconds: 300));
      Object? callError;
      slower
          .post(call)
          .then(
            (_) {},
            onError: (Object e) {
              callError = e;
            },
          );
      int? photoStatus;
      slower.post(photo).then((response) => photoStatus = response.statusCode);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(readError, isA<TimeoutException>());
      expect(callError, isA<TimeoutException>());
      expect(callStatus, 200);
      expect(photoStatus, 200);
    });
  });
}
