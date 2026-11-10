import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/profile/data/marketing_consent_gateway.dart';
import 'package:soolgyul/src/features/profile/presentation/widgets/marketing_consent_control.dart';

class FakeMarketingConsent implements MarketingConsentGateway {
  bool value = true;
  bool fail = false;
  Completer<bool>? pending;
  @override
  Future<bool> load() async {
    if (fail) throw StateError('offline');
    return value;
  }

  @override
  Future<bool> save(bool accepted) async {
    if (fail) throw StateError('offline');
    value = pending == null ? accepted : await pending!.future;
    return value;
  }
}

void main() {
  test(
    'gateway authenticates, sends only desired consent and checks response',
    () async {
      final requests = <http.Request>[];
      Object response = false;
      final client = SupabaseClient(
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
                  'id': 'owner',
                  'aud': 'authenticated',
                  'created_at': '2026-09-01T00:00:00Z',
                  'app_metadata': {},
                  'user_metadata': {},
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          requests.add(request);
          return http.Response(
            jsonEncode(response),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final gateway = SupabaseMarketingConsentGateway(client);
      await expectLater(gateway.load(), throwsStateError);
      expect(requests, isEmpty);
      await client.auth.signInWithPassword(
        email: 'test@example.com',
        password: 'test-password',
      );
      expect(await gateway.load(), false);
      expect(
        requests.last.url.path,
        '/rest/v1/rpc/soolgyul_get_marketing_consent',
      );
      response = true;
      expect(await gateway.save(true), true);
      expect(
        requests.last.url.path,
        '/rest/v1/rpc/soolgyul_set_marketing_consent',
      );
      expect(jsonDecode(requests.last.body), {'p_accepted': true});
      response = 'invalid';
      await expectLater(gateway.load(), throwsStateError);
    },
  );
  testWidgets(
    'loads, waits for save, disables repeats and reloads on reopening',
    (tester) async {
      final gateway = FakeMarketingConsent();
      Widget screen(bool active) => MaterialApp(
        home: Scaffold(
          body: MarketingConsentControl(gateway: gateway, isActive: active),
        ),
      );
      await tester.pumpWidget(screen(true));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
      gateway.pending = Completer<bool>();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
      gateway.pending!.complete(false);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, false);
      await tester.pumpWidget(screen(false));
      gateway.value = true;
      await tester.pumpWidget(screen(true));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    },
  );
  testWidgets('load retry and failed save do not invent success', (
    tester,
  ) async {
    final gateway = FakeMarketingConsent()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarketingConsentControl(gateway: gateway)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('다시 시도'), findsOneWidget);
    gateway.fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    gateway.fail = true;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    expect(find.text('설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });
}
