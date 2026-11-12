import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/features/home/data/supabase_next_drink_guides_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';

import '../support/fake_supabase.dart';
import '../support/memory_saved_views.dart';
import '../support/taste_card_envelopes.dart';

void main() {
  test('a guide row the app cannot read is reported and left out', () async {
    final reported = <(Object, String)>[];
    addTearDown(
      captureErrorReports((error, _, where) => reported.add((error, where))),
    );
    final rows = <Object?>[
      <String, Object?>{
        'result_id': 'card-1',
        'kind_label': '레드 와인',
        'category_label': '와인',
        'guide': defaultGuideJson,
      },
      <String, Object?>{
        'result_id': 'card-2',
        'kind_label': '사케',
        'category_label': null,
        'guide': <String, Object?>{'head': '빠진 칸이 있는 가이드'},
      },
    ];
    final client = fakeSupabaseClient(
      (request) async => http.Response(
        jsonEncode(rows),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      ),
    );
    addTearDown(client.dispose);
    await signInFake(client);
    final phone = MemorySavedViews();
    final gateway = SupabaseNextDrinkGuidesGateway(client, saved: phone);

    final guides = await gateway.load();

    expect(guides.map((guide) => guide.resultId), ['card-1']);
    expect(reported.single.$1, isA<TasteCardWireException>());
    expect(reported.single.$2, 'guides');
    await Future<void>.delayed(Duration.zero);
    expect((await gateway.kept())!.map((guide) => guide.resultId), ['card-1']);
  });
}
