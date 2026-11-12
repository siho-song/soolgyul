import 'dart:convert';
import 'package:soolgyul/src/core/ids.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_draft.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_gateway.dart';
import 'package:soolgyul/src/features/profile/data/supabase_account_completion_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _readyStatus = <String, Object?>{
  'profile_complete': true,
  'display_name': '민지',
  'age_19_or_over_confirmed': true,
  'terms_version': 'soolgyul-terms-v1',
  'privacy_version': 'soolgyul-privacy-v1',
  'marketing_opt_in': false,
  'deletion_state': 'active',
};

CompleteAccountRequest _request([
  ProfileGender gender = ProfileGender.female,
]) => CompleteAccountRequest.fromDraft(
  idempotencyKey: createUuidV4(),
  displayName: '민지',
  draft: AccountCompletionDraft(
    birthYear: AccountCompletionDraft.latestEligibleBirthYear(),
    birthMonth: 1,
    birthDay: 1,
    gender: gender,
    adultAgeConfirmed: true,
    termsAccepted: true,
    privacyAccepted: true,
  ),
);

void main() {
  late SupabaseClient client;
  late List<http.Request> requests;
  late Object? reply;
  var status = 200;

  setUp(() {
    requests = [];
    reply = _readyStatus;
    status = 200;
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(reply),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDown(() => client.dispose());

  test('fetchStatus reads the status straight from the database', () async {
    final gateway = SupabaseAccountCompletionGateway(client);

    final result = await gateway.fetchStatus();

    expect(
      requests.single.url.path,
      '/rest/v1/rpc/soolgyul_get_my_profile_status',
    );
    expect(result.isReady, isTrue);
    expect(result.displayName, '민지');
    expect(result.deletionState, 'active');
    expect(result.marketingOptIn, isFalse);
  });

  test(
    'complete posts the request body and returns the ready status',
    () async {
      final gateway = SupabaseAccountCompletionGateway(client);
      final request = _request();

      final result = await gateway.complete(request);

      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/functions/v1/complete-profile');
      expect(jsonDecode(requests.single.body), request.toJson());
      expect(result.isReady, isTrue);
      expect(result.termsVersion, 'soolgyul-terms-v1');
    },
  );

  test('a response with a renamed or missing field fails closed', () async {
    final gateway = SupabaseAccountCompletionGateway(client);
    // The field name is the contract; a server rename must not read as
    // "profile incomplete" and loop the user back into setup.
    reply = <String, Object?>{..._readyStatus}
      ..remove('profile_complete')
      ..['is_profile_complete'] = true;

    await expectLater(
      gateway.fetchStatus(),
      throwsA(
        isA<AccountCompletionException>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );

    reply = <String, Object?>{..._readyStatus, 'deletion_state': 'purged'};
    await expectLater(
      gateway.complete(_request(ProfileGender.male)),
      throwsA(
        isA<AccountCompletionException>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('a function error carries the public error code', () async {
    final gateway = SupabaseAccountCompletionGateway(client);
    status = 401;
    reply = <String, Object?>{'error_code': 'authorization_required'};

    await expectLater(
      gateway.complete(_request()),
      throwsA(
        isA<AccountCompletionException>()
            .having(
              (error) => error.operation,
              'operation',
              AccountCompletionOperation.complete,
            )
            .having((error) => error.code, 'code', 'authorization_required'),
      ),
    );
  });

  test('a refused status read is a fetchStatus failure', () async {
    final gateway = SupabaseAccountCompletionGateway(client);
    status = 403;
    reply = <String, Object?>{
      'code': '42501',
      'message': 'active_account_required',
    };

    await expectLater(
      gateway.fetchStatus(),
      throwsA(
        isA<AccountCompletionException>().having(
          (error) => error.operation,
          'operation',
          AccountCompletionOperation.fetchStatus,
        ),
      ),
    );
  });
}
