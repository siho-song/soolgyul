import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:soolgyul/src/features/records/data/supabase_tasting_note_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_supabase.dart';

const owner = '10000000-0000-0000-0000-000000000001';
const recordId = '30000000-0000-4000-8000-000000000001';

void main() {
  late SupabaseClient client;
  late SupabaseTastingNoteGateway gateway;
  late List<http.Request> requests;
  Object? responseBody;

  setUp(() async {
    requests = [];
    responseBody = null;
    client = fakeSupabaseClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(responseBody),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }, userId: owner);
    await signInFake(client);
    gateway = SupabaseTastingNoteGateway(client);
  });
  tearDown(() => client.dispose());

  test('the occasion, the stars and the ways are read as the app holds '
      'them; a whole star reads without its .0', () async {
    responseBody = {
      'rating': 4.5,
      'purchased_on': '2026-09-01',
      'companion_place': '친구와 집에서',
      'pairing': ' 스테이크 ',
      'serving': ['breathing', 'decanting'],
      'aroma_memo': null,
    };
    expect(await gateway.load(recordId), {
      'rating': '4.5',
      'purchased_on': '2026-09-01',
      'companion_place': '친구와 집에서',
      'pairing': '스테이크',
      'serving': 'breathing,decanting',
    });
    responseBody = {'rating': 4.0};
    expect(await gateway.load(recordId), {'rating': '4'});
    final select = requests.first.url.queryParameters['select']!;
    for (final column in ['rating', 'purchased_on', 'companion_place']) {
      expect(select, contains(column));
    }
  });

  test('the stars go to the owner RPC as a number, and none clears '
      'them', () async {
    await gateway.save(recordId, {
      'rating': '4.5',
      'purchased_on': '2026-09-01',
      'serving': 'neat,rocks',
    });
    await gateway.save(recordId, {'rating': '4'});
    await gateway.save(recordId, {'rating': null});
    expect(
      [for (final request in requests) jsonDecode(request.body)['p_note']],
      [
        {
          'rating': 4.5,
          'purchased_on': '2026-09-01',
          'serving': ['neat', 'rocks'],
        },
        {'rating': 4},
        {'rating': null},
      ],
    );
  });
}
