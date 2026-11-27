import 'dart:async';

import 'package:soolgyul/src/core/errors/connection_failure.dart';
import 'package:soolgyul/src/core/catalog/drink_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/profile/presentation/profile_screens.dart';

Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(411, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('NicknameEditSheet', () {
    final field = find.descendant(
      of: find.byKey(const ValueKey('profile-nickname-field')),
      matching: find.byType(EditableText),
    );
    final feedback = find.byKey(const ValueKey('profile-nickname-feedback'));
    final save = find.byKey(const ValueKey('profile-save-button'));

    String feedbackText(WidgetTester tester) =>
        tester.widget<Text>(feedback).data!;

    Future<void> openSheet(WidgetTester tester, NicknameSaver onSave) async {
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showNicknameEditSheet(
              context,
              initialNickname: '술결',
              onSave: onSave,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a message for each invalid nickname', (tester) async {
      final saved = <String>[];
      await openSheet(tester, (nickname) async {
        saved.add(nickname);
        return true;
      });
      expect(feedbackText(tester), '사용 가능한 닉네임이에요.');

      const cases = <String, String>{
        '': '닉네임을 입력해 주세요.',
        '술 결': '띄어쓰기 없이 입력해 주세요.',
        '술결!': '한글, 영문, 숫자만 사용할 수 있어요.',
        '술': '2자 이상으로 입력해 주세요.',
      };
      for (final entry in cases.entries) {
        await tester.enterText(field, entry.key);
        await tester.pump();
        expect(feedbackText(tester), entry.value, reason: entry.key);
        await tester.tap(save);
        await tester.pump();
        expect(saved, isEmpty, reason: entry.key);
      }
    });

    testWidgets('saves a valid nickname, counts it and closes', (tester) async {
      final saved = <String>[];
      await openSheet(tester, (nickname) async {
        saved.add(nickname);
        return true;
      });
      await tester.enterText(field, 'Soolgyul12');
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('profile-nickname-count')))
            .data,
        '10 / 12',
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved, <String>['Soolgyul12']);
      expect(find.byType(NicknameEditSheet), findsNothing);
    });

    testWidgets('a failed save keeps the sheet open with the message', (
      tester,
    ) async {
      await openSheet(tester, (_) async => false);
      await tester.enterText(field, '새닉네임');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(NicknameEditSheet), findsOneWidget);
      expect(feedbackText(tester), '저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
    });

    testWidgets('a save that throws says what it failed with: the connection '
        'as one, anything else in the sheet\'s own line', (tester) async {
      Object failure = ConnectionFailure('no route');
      await openSheet(tester, (_) async => throw failure);
      await tester.enterText(field, '새닉네임');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(NicknameEditSheet), findsOneWidget);
      expect(feedbackText(tester), '네트워크 연결이 불안정해요. 연결을 확인한 뒤 다시 시도해 주세요.');

      failure = StateError('refused');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(feedbackText(tester), '저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
    });

    testWidgets('a sheet closed while its save runs leaves the failure to '
        'the page under it', (tester) async {
      for (final (failure, line) in <(Object, String)>[
        (
          ConnectionFailure('no route'),
          '네트워크 연결이 불안정해요. 연결을 확인한 뒤 다시 시도해 주세요.',
        ),
        (StateError('refused'), '저장하지 못했어요. 잠시 후 다시 시도해 주세요.'),
      ]) {
        final answer = Completer<bool>();
        await openSheet(tester, (_) => answer.future);
        await tester.enterText(field, '새닉네임');
        await tester.tap(save);
        await tester.pump();
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        expect(find.byType(NicknameEditSheet), findsNothing);
        answer.completeError(failure);
        await tester.pumpAndSettle();
        expect(find.text(line), findsOneWidget, reason: '$failure');
      }
    });
  });

  group('DrinkInterestSheet', () {
    final complete = find.byKey(const ValueKey('profile-drink-complete'));

    Future<void> openSheet(
      WidgetTester tester, {
      required Set<DrinkType> initial,
      required DrinkInterestSaver onSave,
    }) async {
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDrinkInterestSheet(
              context,
              initialSelection: initial,
              onSave: onSave,
            ),
            child: const Text('열기'),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
    }

    testWidgets('toggles interests, saves the selection and closes', (
      tester,
    ) async {
      Set<DrinkType>? saved;
      await openSheet(
        tester,
        initial: const {DrinkType.wine},
        onSave: (value) async {
          saved = value;
          return true;
        },
      );
      expect(find.text('관심 주종 설정'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('profile-drink-위스키')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('profile-drink-와인')));
      await tester.pump();
      await tester.tap(complete);
      await tester.pumpAndSettle();
      expect(saved, {DrinkType.whisky});
      expect(find.byType(DrinkInterestSheet), findsNothing);
    });

    testWidgets('a failed save keeps the sheet open and says so', (
      tester,
    ) async {
      await openSheet(
        tester,
        initial: const {DrinkType.wine},
        onSave: (_) async => false,
      );
      await tester.tap(complete);
      await tester.pumpAndSettle();
      expect(find.byType(DrinkInterestSheet), findsOneWidget);
      expect(find.text('관심 주종을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    });

    testWidgets('a save the connection failed says the connection', (
      tester,
    ) async {
      await openSheet(
        tester,
        initial: const {DrinkType.wine},
        onSave: (_) async => throw ConnectionFailure('no route'),
      );
      await tester.tap(complete);
      await tester.pumpAndSettle();
      expect(find.byType(DrinkInterestSheet), findsOneWidget);
      expect(
        find.text('네트워크 연결이 불안정해요. 연결을 확인한 뒤 다시 시도해 주세요.'),
        findsOneWidget,
      );
      expect(find.textContaining('관심 주종을 저장하지'), findsNothing);
    });

    testWidgets('a sheet closed while its save runs leaves the failure to '
        'the page under it', (tester) async {
      final answer = Completer<bool>();
      await openSheet(
        tester,
        initial: const {DrinkType.wine},
        onSave: (_) => answer.future,
      );
      await tester.tap(complete);
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(DrinkInterestSheet), findsNothing);
      answer.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('관심 주종을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    });

    testWidgets('disables an empty selection', (tester) async {
      var saves = 0;
      await openSheet(
        tester,
        initial: const {DrinkType.wine},
        onSave: (_) async {
          saves++;
          return true;
        },
      );
      const reason = '관심 주종을 하나 이상 선택해 주세요.';
      expect(find.text(reason), findsNothing);
      await tester.tap(find.byKey(const ValueKey('profile-drink-와인')));
      await tester.pump();
      // Why 저장 cannot be pressed stands over it.
      expect(find.text(reason), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text(reason)).dy,
        lessThan(tester.getTopLeft(complete).dy),
      );
      await tester.tap(complete);
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(find.byType(DrinkInterestSheet), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('profile-drink-위스키')));
      await tester.pump();
      expect(find.text(reason), findsNothing);
    });
  });
}
