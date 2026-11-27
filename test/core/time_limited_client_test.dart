import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/core/errors/connection_failure.dart';
import 'package:soolgyul/src/core/supabase/time_limited_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestClient;

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

/// A request ended by its time limit.
final _timedOut = isA<ConnectionFailure>().having(
  (failure) => failure.cause,
  'cause',
  isA<TimeoutException>(),
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
      expect(timeouts, everyElement(_timedOut));
      expect(timeouts, hasLength(3));
    });
  });

  test('a request the connection failed is a ConnectionFailure, whatever the '
      'platform threw; any other failure passes as it is', () async {
    TimeLimitedClient failing(Object error) =>
        TimeLimitedClient(inner: MockClient((_) async => throw error));
    await expectLater(
      failing(http.ClientException('no route to host')).get(read),
      throwsA(
        isA<ConnectionFailure>().having(
          (failure) => failure.cause,
          'cause',
          isA<http.ClientException>(),
        ),
      ),
    );
    await expectLater(
      failing(StateError('a bug')).get(read),
      throwsA(isA<StateError>()),
    );
  });

  test('the database client asks a read the connection failed once, not '
      'four times, and the screen hears of it at once', () {
    fakeAsync((async) {
      var sends = 0;
      final database = PostgrestClient(
        'https://example.test/rest/v1',
        httpClient: TimeLimitedClient(
          inner: MockClient((_) async {
            sends++;
            throw http.ClientException('no route to host');
          }),
        ),
      );
      Object? failure;
      database
          .from('taste_letters')
          .select()
          .then(
            (_) {},
            onError: (Object error) {
              failure = error;
            },
          );

      // Before the client's first wait of a second would have ended.
      async.elapse(const Duration(milliseconds: 100));
      expect(failure, isA<ConnectionFailure>());
      async.elapse(const Duration(seconds: 30));
      expect(sends, 1);
    });
  });

  test('a read the server answered 503 is still asked again by the database '
      'client', () {
    fakeAsync((async) {
      var sends = 0;
      final database = PostgrestClient(
        'https://example.test/rest/v1',
        httpClient: TimeLimitedClient(
          inner: MockClient((request) async {
            sends++;
            return http.Response(
              '[]',
              sends == 1 ? 503 : 200,
              request: request,
            );
          }),
        ),
      );
      database.from('taste_letters').select().then((_) {});
      async.elapse(const Duration(seconds: 5));
      expect(sends, 2);
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
      expect(readError, _timedOut);
      expect(callError, _timedOut);
      expect(callStatus, 200);
      expect(photoStatus, 200);
    });
  });
}
