import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/profile/data/account_deletion_gateway.dart';
import 'package:soolgyul/src/features/profile/presentation/account_deleting_sheet.dart';
import 'package:soolgyul/src/features/profile/presentation/legal_document_link.dart';
import 'package:soolgyul/src/features/profile/presentation/profile_screens.dart';
import 'package:soolgyul/src/widgets/app_sheet.dart';

class FakeDeletionGateway implements AccountDeletionGateway {
  int restores = 0;
  int deletions = 0;
  bool fail = false;
  @override
  Future<void> restore() async {
    restores++;
    if (fail) throw const AccountDeletionException('복구 실패');
  }

  @override
  Future<void> requestDeletion() async {
    deletions++;
    if (fail) throw const AccountDeletionException('연결 해제 실패');
  }

  @override
  Future<AccountDeletionStatus> fetchStatus() async =>
      const AccountDeletionStatus(state: 'scheduled');
}

void main() {
  group('PolicyScreen', () {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    var succeeds = true;
    setUp(() {
      calls.clear();
      succeeds = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return succeeds;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    testWidgets(
      'withdrawal notice invokes confirmed action and reports failure without claiming success',
      (tester) async {
        var requests = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PolicyScreen(
                onSignOut: () async {},
                onRequestAccountDeletion: () async {
                  requests++;
                  throw const AccountDeletionException('연결 해제 실패');
                },
              ),
            ),
          ),
        );
        final entry = find.byKey(
          const ValueKey<String>('policy-account-deletion'),
        );
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(requests, 0);
        await tester.tap(
          find.byKey(const ValueKey<String>('policy-account-deletion-request')),
        );
        await tester.pumpAndSettle();
        expect(requests, 1);
        expect(find.text('연결 해제 실패'), findsOneWidget);
      },
    );

    test(
      'documents use public HTTPS URLs without account or token parameters',
      () {
        expect(
          legalDocumentUri(LegalDocument.terms).toString(),
          'https://soolgyul.com/terms/',
        );
        expect(
          legalDocumentUri(LegalDocument.privacy).toString(),
          'https://soolgyul.com/privacy/',
        );
        expect(
          legalDocumentUri(LegalDocument.notice).toString(),
          'https://soolgyul.com/notice/',
        );
        expect(
          legalDocumentUri(LegalDocument.faq).toString(),
          'https://soolgyul.com/faq/',
        );
      },
    );

    testWidgets('support center opens the FAQ web page', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SupportCenterScreen(onInquiry: () {})),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('support-faq-entry')));
      await tester.pumpAndSettle();
      expect(calls.last.arguments['url'], 'https://soolgyul.com/faq/');
      expect(find.text('1:1 문의'), findsWidgets);
    });

    testWidgets(
      'policy menus open distinct web pages and leave app route intact',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: PolicyScreen(onSignOut: () async {})),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('서비스 이용약관'));
        await tester.pumpAndSettle();
        expect(calls.last.arguments['url'], 'https://soolgyul.com/terms/');
        expect(calls.last.arguments['useSafariVC'], true);
        await tester.tap(find.text('개인정보 처리방침'));
        await tester.pumpAndSettle();
        expect(calls.last.arguments['url'], 'https://soolgyul.com/privacy/');
        expect(find.byType(PolicyScreen), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
      },
    );

    testWidgets(
      'launch failure shows retry message instead of claiming success',
      (tester) async {
        succeeds = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      openLegalDocument(context, LegalDocument.privacy),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
        expect(calls, hasLength(2));
        expect(find.text('페이지를 불러오지 못했어요. 네트워크 연결을 확인해 주세요.'), findsOneWidget);
      },
    );
  });

  group('AccountDeletingSheet', () {
    testWidgets('tells that the window is over and of signing up again, '
        'and only confirms', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppSheet<void>(
                  context: context,
                  dismissible: false,
                  builder: (_) => const AccountDeletingSheet(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('계정을 삭제하고 있어요'), findsOneWidget);
      expect(find.textContaining('다시 가입할 수 있어요'), findsOneWidget);
      expect(find.text('계정 복구'), findsNothing);
      expect(find.text('탈퇴 유지'), findsNothing);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountDeletingSheet), findsNothing);
    });
  });
}
