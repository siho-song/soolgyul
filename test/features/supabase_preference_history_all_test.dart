import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:soolgyul/src/features/preferences/data/supabase_preference_history_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_supabase.dart';
import '../support/memory_saved_views.dart';

// 기록 검색 reads every record. The server answers no span wider than 45
// days, so the gateway asks span by span from the oldest record to now.

void main() {
  late SupabaseClient client;
  late MemorySavedViews phone;

  /// When each record on the server was made, in no order.
  late List<DateTime> made;

  /// The spans the history was asked for.
  late List<(DateTime, DateTime)> spans;

  setUp(() async {
    spans = <(DateTime, DateTime)>[];
    phone = MemorySavedViews(account: 'user-1');
    client = fakeSupabaseClient((request) async {
      final path = request.url.path;
      final Object body;
      if (path.endsWith('/drink_records')) {
        expect(
          request.url.queryParameters['order'],
          startsWith('created_at.asc'),
          reason: 'the oldest record, not the newest',
        );
        final oldest = made.isEmpty
            ? null
            : made.reduce((a, b) => a.isBefore(b) ? a : b);
        body = <Object?>[
          if (oldest != null)
            <String, Object?>{'created_at': oldest.toIso8601String()},
        ];
      } else if (path.endsWith('/soolgyul_my_drink_history')) {
        final params = jsonDecode(request.body) as Map<String, dynamic>;
        final from = DateTime.parse(params['p_from'] as String);
        final to = DateTime.parse(params['p_to'] as String);
        spans.add((from, to));
        final inSpan =
            made.where((at) => !at.isBefore(from) && at.isBefore(to)).toList()
              ..sort();
        body = <Object?>[
          for (final at in inSpan)
            <String, Object?>{
              'result_id': 'card-${made.indexOf(at)}',
              'recorded_at': at.toIso8601String(),
              'name': '술 ${made.indexOf(at)}',
              'category_label': '와인',
            },
        ];
      } else {
        body = <Object?>[];
      }
      return http.Response(
        jsonEncode(body),
        200,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    await signInFake(client);
  });
  tearDown(() => client.dispose());

  test('every record comes newest first, asked in spans the server '
      'answers, and none is kept on the phone', () async {
    final now = DateTime.now().toUtc();
    made = <DateTime>[
      now.subtract(const Duration(days: 30)),
      now.subtract(const Duration(days: 200)),
      now.subtract(const Duration(hours: 1)),
      now.subtract(const Duration(days: 31)),
    ];

    final records = await SupabasePreferenceHistoryGateway(
      client,
      saved: phone,
    ).loadAll();

    expect(
      [for (final record in records) record.resultId],
      ['card-2', 'card-0', 'card-3', 'card-1'],
    );
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    expect(spans, hasLength(5), reason: '200 days in spans of 45');
    for (final (from, to) in spans) {
      expect(to.difference(from), const Duration(days: 45));
    }
    for (var index = 1; index < spans.length; index++) {
      expect(
        spans[index].$1,
        spans[index - 1].$2,
        reason: 'no gap, no overlap',
      );
    }
    expect(spans.first.$1.isAfter(made[1]), isFalse);
    expect(spans.last.$2.isAfter(now), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(phone.copies, isEmpty);
  });

  test('an account without a record asks for no history', () async {
    made = <DateTime>[];
    expect(await SupabasePreferenceHistoryGateway(client).loadAll(), isEmpty);
    expect(spans, isEmpty);
  });
}
