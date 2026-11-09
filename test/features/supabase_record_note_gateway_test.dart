import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/features/records/data/record_note_gateway.dart';
import 'package:soolgyul/src/features/records/data/supabase_record_note_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const owner = '10000000-0000-0000-0000-000000000001';
const recordId = '30000000-0000-4000-8000-000000000001';

void main() {
  late SupabaseClient client;
  late SupabaseRecordNoteGateway gateway;
  late List<http.Request> requests;
  var rpcFails = false;
  Object? responseBody;

  setUp(() async {
    requests = [];
    rpcFails = false;
    responseBody = null;
    client = SupabaseClient(
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
                'id': owner,
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
        requests.add(request);
        return http.Response(
          jsonEncode(
            rpcFails ? {'message': 'not owner', 'code': 'P0001'} : responseBody,
          ),
          rpcFails ? 400 : 200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-password',
    );
    gateway = SupabaseRecordNoteGateway(client);
  });
  tearDown(() => client.dispose());

  test('the note goes to the owner RPC as typed', () async {
    await gateway.saveNote(recordId: recordId, note: '  뒤에 달큰함이 남았어요 ');
    final rpc = requests.single;
    expect(rpc.url.path, '/rest/v1/rpc/soolgyul_update_my_drink_record_note');
    expect(jsonDecode(rpc.body), {
      'p_record_id': recordId,
      'p_note': '  뒤에 달큰함이 남았어요 ',
    });
  });

  test('the note is read from the owner\'s record row', () async {
    responseBody = {'one_line_note': '향이 오래 남았어요'};
    expect(await gateway.loadNote(recordId), '향이 오래 남았어요');
    final read = requests.single;
    expect(read.method, 'GET');
    expect(read.url.path, '/rest/v1/drink_records');
    expect(read.url.queryParameters, {
      'select': 'one_line_note',
      'id': 'eq.$recordId',
    });

    responseBody = {'one_line_note': null};
    expect(await gateway.loadNote(recordId), '');
  });

  test('a rejected update surfaces as a note exception', () async {
    rpcFails = true;
    await expectLater(
      gateway.saveNote(recordId: recordId, note: '메모'),
      throwsA(isA<RecordNoteException>()),
    );
  });

  test('signed out, the note is not sent', () async {
    await client.auth.signOut(scope: SignOutScope.local);
    requests.clear();
    await expectLater(
      gateway.saveNote(recordId: recordId, note: '메모'),
      throwsA(isA<RecordNoteException>()),
    );
    expect(requests, isEmpty);
  });
}
