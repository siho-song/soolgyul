import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/profile/data/account_deletion_gateway.dart';
import 'package:soolgyul/src/features/profile/presentation/account_deleting_dialog.dart';
import 'package:soolgyul/src/features/profile/presentation/legal_document_link.dart';
import 'package:soolgyul/src/features/profile/presentation/profile_screens.dart';
import 'package:soolgyul/src/widgets/app_button.dart';
import 'package:soolgyul/src/widgets/app_dialog.dart';
import 'package:soolgyul/src/widgets/app_state_view.dart';

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
        // A popup like the sign-out's, not a sheet: its name, the two
        // sentences and the two buttons, and nothing else.
        expect(find.byType(AppDialogBody), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AppDialogBody),
            matching: find.text('계정 삭제'),
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            '7일 이내에 로그인하면 삭제가 취소되고 계정이 복구돼요.\n\n'
            '삭제 후에는 데이터를 복구할 수 없어요.',
          ),
          findsOneWidget,
        );
        expect(find.text('취소'), findsOneWidget);
        expect(find.text('삭제'), findsOneWidget);
        expect(find.textContaining('로그인 창'), findsNothing);
        expect(find.textContaining('30일'), findsNothing);
        expect(find.textContaining('탈퇴'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey<String>('policy-account-deletion-request')),
        );
        await tester.pumpAndSettle();
        expect(requests, 1);
        expect(find.text('연결 해제 실패'), findsOneWidget);
      },
    );

    testWidgets('the row turns while the request is on its way; 취소 asks '
        'for nothing', (tester) async {
      final request = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PolicyScreen(
              onSignOut: () async {},
              onRequestAccountDeletion: () => request.future,
            ),
          ),
        ),
      );
      final entry = find.byKey(
        const ValueKey<String>('policy-account-deletion'),
      );
      Finder spinnerIn(Finder row) =>
          find.descendant(of: row, matching: find.byType(AppSmallSpinner));
      expect(spinnerIn(entry), findsNothing);
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialogBody), findsNothing);
      expect(spinnerIn(entry), findsNothing);

      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('policy-account-deletion-request')),
      );
      // The spinner turns, so the frames never settle while it shows.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(spinnerIn(entry), findsOneWidget);
      expect(
        spinnerIn(find.byKey(const ValueKey<String>('policy-sign-out'))),
        findsNothing,
      );

      request.completeError(
        const AccountDeletionException('본인 확인을 취소해서 계정 삭제를 요청하지 않았어요.'),
      );
      await tester.pumpAndSettle();
      expect(spinnerIn(entry), findsNothing);
      expect(find.text('본인 확인을 취소해서 계정 삭제를 요청하지 않았어요.'), findsOneWidget);
    });

    testWidgets('the row is named 계정 삭제, and where the request cannot be '
        'made yet the popup\'s button is off', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PolicyScreen(onSignOut: () async {})),
        ),
      );
      final entry = find.byKey(
        const ValueKey<String>('policy-account-deletion'),
      );
      expect(
        find.descendant(of: entry, matching: find.text('계정 삭제')),
        findsOneWidget,
      );
      expect(find.text('회원 탈퇴'), findsNothing);
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      final request = tester.widget<AppButton>(
        find.byKey(const ValueKey<String>('policy-account-deletion-request')),
      );
      expect(request.label, '잠시 후 이용 가능');
      expect(request.isDisabled, isTrue);
      await tester.tap(find.byWidget(request), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialogBody), findsOneWidget);
    });

    testWidgets('signing out turns its row until it is done', (tester) async {
      final signOut = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PolicyScreen(onSignOut: () => signOut.future)),
        ),
      );
      final row = find.byKey(const ValueKey<String>('policy-sign-out'));
      Finder spinner() =>
          find.descendant(of: row, matching: find.byType(AppSmallSpinner));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('policy-sign-out-confirm')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(spinner(), findsOneWidget);

      signOut.complete();
      await tester.pumpAndSettle();
      expect(spinner(), findsNothing);
    });

    test(
      'documents use public HTTPS URLs without account or token parameters',
      () {
        expect(
          legalDocumentUri(LegalDocument.terms).toString(),
          'https://soolgyul.com/terms/?from=app',
        );
        expect(
          legalDocumentUri(LegalDocument.privacy).toString(),
          'https://soolgyul.com/privacy/?from=app',
        );
        expect(
          legalDocumentUri(LegalDocument.notice).toString(),
          'https://soolgyul.com/notice/?from=app',
        );
      },
    );

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
        expect(
          calls.last.arguments['url'],
          'https://soolgyul.com/terms/?from=app',
        );
        expect(calls.last.arguments['useSafariVC'], true);
        await tester.tap(find.text('개인정보 처리방침'));
        await tester.pumpAndSettle();
        expect(
          calls.last.arguments['url'],
          'https://soolgyul.com/privacy/?from=app',
        );
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

  group('AccountDeletingDialog', () {
    testWidgets('tells that the window is over and of signing up again, '
        'and only confirms', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppDialog<void>(
                  context: context,
                  dismissible: false,
                  builder: (_) => const AccountDeletingDialog(),
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
      expect(find.byType(AccountDeletingDialog), findsNothing);
    });
  });
}
