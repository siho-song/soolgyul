import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/design/app_tokens.dart';
import 'package:soolgyul/src/features/profile/presentation/account_deleting_dialog.dart';
import 'package:soolgyul/src/features/profile/presentation/profile_screens.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/record_delete_dialog.dart';
import 'package:soolgyul/src/widgets/app_button.dart';
import 'package:soolgyul/src/widgets/app_dialog.dart';

// A popup is the phone's own alert on an iPhone and the app's card
// elsewhere, from the same title, sentence and buttons.

const _stay = ValueKey<String>('stay');
const _go = ValueKey<String>('go');

/// A page whose button opens a two-button popup and keeps its answer.
Future<List<bool?>> _pumpAsker(WidgetTester tester) async {
  final answers = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              await showAppDialog<bool>(
                context: context,
                builder: (context) => AppDialogBody(
                  title: '로그아웃 확인',
                  body: '로그인 상태가 해제돼요.',
                  actions: <Widget>[
                    AppButton(
                      key: _stay,
                      label: '취소',
                      variant: AppButtonVariant.neutral,
                      size: AppButtonSize.popup,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    AppButton(
                      key: _go,
                      label: '확인',
                      size: AppButtonSize.popup,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  return answers;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

final _iPhone = TargetPlatformVariant.only(TargetPlatform.iOS);
final _android = TargetPlatformVariant.only(TargetPlatform.android);

void main() {
  testWidgets(
    'on Android a popup is the app\'s own card with its buttons',
    (tester) async {
      final answers = await _pumpAsker(tester);
      await _open(tester);

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(tester.widget(find.byKey(_stay)), isA<AppButton>());
      expect(find.text('로그아웃 확인'), findsOneWidget);
      expect(find.text('로그인 상태가 해제돼요.'), findsOneWidget);

      await tester.tap(find.byKey(_go));
      await tester.pumpAndSettle();
      await _open(tester);
      await tester.tap(find.byKey(_stay));
      await tester.pumpAndSettle();
      expect(answers, [true, false]);
    },
    variant: _android,
  );

  testWidgets('on an iPhone the same popup is the phone\'s alert: the way '
      'back in ink, the action in the app\'s colour, both in the app\'s '
      'typeface and under the same keys', (tester) async {
    final answers = await _pumpAsker(tester);
    await _open(tester);

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AppButton), findsNothing);
    expect(find.text('로그아웃 확인'), findsOneWidget);
    expect(find.text('로그인 상태가 해제돼요.'), findsOneWidget);

    CupertinoDialogAction action(Key key) =>
        tester.widget<CupertinoDialogAction>(find.byKey(key));
    expect(action(_stay).textStyle!.color, AppColors.textPrimary);
    expect(action(_go).textStyle!.color, AppColors.actionPrimary);
    for (final key in [_stay, _go]) {
      expect(action(key).textStyle!.fontFamily, AppFonts.body);
    }
    // The words as they are drawn, not only as they were asked for.
    TextStyle drawn(String text) => tester
        .widget<RichText>(
          find.descendant(of: find.text(text), matching: find.byType(RichText)),
        )
        .text
        .style!;
    expect(drawn('취소').color, AppColors.textPrimary);
    expect(drawn('확인').color, AppColors.actionPrimary);
    for (final text in ['로그아웃 확인', '로그인 상태가 해제돼요.', '취소', '확인']) {
      expect(drawn(text).fontFamily, AppFonts.body, reason: text);
    }
    // The way back first, the action second.
    expect(
      tester.getCenter(find.byKey(_stay)).dx,
      lessThan(tester.getCenter(find.byKey(_go)).dx),
    );

    await tester.tap(find.byKey(_go));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    await _open(tester);
    await tester.tap(find.byKey(_stay));
    await tester.pumpAndSettle();
    expect(answers, [true, false]);
  }, variant: _iPhone);

  testWidgets('on an iPhone a busy button turns and the one beside it is '
      'off, as on the card deleted from its popup', (tester) async {
    final deleting = Completer<void>();
    var deletes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppDialog<void>(
              context: context,
              builder: (_) => RecordDeleteDialog(
                onDelete: () {
                  deletes++;
                  return deleting.future;
                },
              ),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await _open(tester);
    const cancel = ValueKey<String>('record-delete-cancel');
    const confirm = ValueKey<String>('record-delete-confirm');
    CupertinoDialogAction action(Key key) =>
        tester.widget<CupertinoDialogAction>(find.byKey(key));
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(action(cancel).onPressed, isNotNull);

    await tester.tap(find.byKey(confirm));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(confirm),
        matching: find.byType(CupertinoActivityIndicator),
      ),
      findsOneWidget,
    );
    expect(action(confirm).onPressed, isNull);
    expect(action(cancel).onPressed, isNull);
    await tester.tap(find.byKey(confirm), warnIfMissed: false);
    await tester.pump();
    expect(deletes, 1);

    deleting.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  }, variant: _iPhone);

  testWidgets(
    'a screen that asks through a popup works the same on both '
    'phones: signing out',
    (tester) async {
      var signOuts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: PolicyScreen(onSignOut: () async => signOuts++)),
        ),
      );
      final row = find.byKey(const ValueKey<String>('policy-sign-out'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        find.byType(CupertinoAlertDialog),
        defaultTargetPlatform == TargetPlatform.iOS
            ? findsOneWidget
            : findsNothing,
      );
      expect(find.text('로그아웃 확인'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('policy-sign-out-confirm')),
      );
      await tester.pumpAndSettle();
      expect(signOuts, 1);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets('a notice with one button is one row of the alert', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppDialog<void>(
              context: context,
              dismissible: false,
              builder: (_) => const AccountDeletingDialog(),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await _open(tester);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('계정을 삭제하고 있어요'), findsOneWidget);
    expect(find.byType(CupertinoDialogAction), findsOneWidget);
    // It must be answered: a tap outside leaves it up.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('account-deleting-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  }, variant: _iPhone);
}
