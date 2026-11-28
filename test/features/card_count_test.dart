import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:soolgyul/src/features/records/data/card_count.dart';
import 'package:soolgyul/src/features/records/data/supabase_card_count.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_supabase.dart';

// How many cards the account has: what 기록하기 reads to tell a first record
// from the ones after it.

void main() {
  test('the count is unknown until read, kept once read, kept when a later '
      'read fails, and forgotten at sign-out', () async {
    var cards = 0;
    Object? failure;
    final container = ProviderContainer(
      overrides: [
        cardCountLoaderProvider.overrideWithValue(() async {
          if (failure case final failure?) throw failure;
          return cards;
        }),
      ],
    );
    addTearDown(container.dispose);
    final counter = container.read(cardCountProvider.notifier);

    expect(container.read(cardCountProvider), isNull);
    expect(await counter.load(), 0);
    expect(container.read(cardCountProvider), 0);

    cards = 1;
    expect(await counter.load(), 1);
    expect(container.read(cardCountProvider), 1);

    failure = StateError('offline');
    await expectLater(counter.load(), throwsStateError);
    expect(container.read(cardCountProvider), 1);

    counter.clear();
    expect(container.read(cardCountProvider), isNull);
  });

  test('without a loader nothing is read', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(cardCountProvider.notifier).load(), isNull);
    expect(container.read(cardCountProvider), isNull);
  });

  test('the server is asked for the account\'s own records that have a '
      'card, counted and not read', () async {
    final requests = <http.Request>[];
    final client = fakeSupabaseClient((request) async {
      requests.add(request);
      return http.Response(
        '[]',
        200,
        request: request,
        headers: {'content-type': 'application/json', 'content-range': '*/37'},
      );
    });
    addTearDown(client.dispose);
    await signInFake(client);
    expect(await SupabaseCardCount(client).load(), 37);
    final request = requests.single;
    expect(request.url.path, endsWith('/drink_records'));
    expect(request.url.queryParameters['user_id'], 'eq.user-1');
    expect(request.url.queryParameters['select'], 'id,taste_cards!inner(id)');
    expect(request.headers['Prefer'], contains('count=exact'));
  });

  test('a missing session fails instead of claiming no cards', () async {
    final client = SupabaseClient('https://example.supabase.co', 'test-key');
    addTearDown(client.dispose);
    await expectLater(SupabaseCardCount(client).load(), throwsStateError);
  });
}
