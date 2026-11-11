import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/core/async_shown.dart';
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/core/supabase/time_limited_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<(Object, String)> reported;

  setUp(() {
    reported = <(Object, String)>[];
    addTearDown(
      captureErrorReports((error, _, where) => reported.add((error, where))),
    );
  });

  test('a fault is reported; no network and a closed login are not', () {
    reportError(
      StateError('a field is missing'),
      StackTrace.current,
      where: 'card',
    );
    reportError(TimeoutException('slow'), StackTrace.current, where: 'card');
    reportError(
      http.ClientException('no route to host'),
      StackTrace.current,
      where: 'card',
    );
    reportError(
      AuthRetryableFetchException(),
      StackTrace.current,
      where: 'session',
    );

    expect(reported, hasLength(1));
    expect(reported.single.$1, isA<StateError>());
    expect(reported.single.$2, 'card');
  });

  test('a load that failed after a sign-out is reported as what it failed '
      'with', () {
    reportError(
      FailedSinceSignOut(const FormatException('bad row')),
      StackTrace.current,
      where: 'load',
    );
    expect(reported.single.$1, isA<FormatException>());

    reported.clear();
    reportError(
      FailedSinceSignOut(TimeoutException('slow')),
      StackTrace.current,
      where: 'load',
    );
    expect(reported, isEmpty);
  });

  test('a message loses addresses, tokens and long runs before it leaves', () {
    final cleaned = scrubbed(
      'row (minji@example.com, eyJhbGciOi.eyJzdWIiOiIx.c2lnbmF0dXJl, '
      '${'a' * 64}) ${'가' * 400}',
    );
    expect(cleaned, isNot(contains('minji')));
    expect(cleaned, isNot(contains('eyJ')));
    expect(cleaned, isNot(contains('a' * 40)));
    expect(cleaned.length, lessThanOrEqualTo(301));
  });

  test('a route names the call and nothing a member put in the path', () {
    String route(String path) =>
        ServerFailure.routeOf(Uri.parse('https://x.supabase.co$path'));
    expect(route('/functions/v1/taste-fit'), '/functions/v1/taste-fit');
    expect(
      route('/rest/v1/rpc/soolgyul_my_liked_cards'),
      '/rest/v1/rpc/soolgyul_my_liked_cards',
    );
    expect(route('/rest/v1/users?id=eq.123'), '/rest/v1/users');
    expect(
      route(
        '/storage/v1/object/soolgyul-private/member-id/inquiries/x/0-a.jpg',
      ),
      '/storage/v1/object',
    );
  });

  test('every request passes one client, which notes a fault of the '
      'server and nothing else', () async {
    var status = 200;
    final client = TimeLimitedClient(
      inner: MockClient((_) async => http.Response('{}', status)),
    );

    await client.get(Uri.parse('https://x.supabase.co/rest/v1/users?id=eq.1'));
    status = 404;
    await client.get(Uri.parse('https://x.supabase.co/rest/v1/users?id=eq.1'));
    expect(reported, isEmpty);

    status = 503;
    final response = await client.post(
      Uri.parse('https://x.supabase.co/functions/v1/taste-fit'),
    );
    expect(response.statusCode, 503);
    final failure = reported.single.$1 as ServerFailure;
    expect(
      (failure.status, failure.method, failure.route),
      (503, 'POST', '/functions/v1/taste-fit'),
    );
    expect(reported.single.$2, 'server');
  });
}
