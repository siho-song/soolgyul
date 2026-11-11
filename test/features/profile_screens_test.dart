import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/profile/presentation/profile_screens.dart';
import 'package:soolgyul/src/features/profile/data/profile_setup_draft.dart';

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

    testWidgets('keeps the nickname field compact', (tester) async {
      await openSheet(tester, (_) async => true);
      final height = tester
          .getSize(find.byKey(const ValueKey('profile-nickname-field')))
          .height;
      // 12px above and below the 16px nickname line.
      expect(height, 48);
    });

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
  });

  group('DrinkInterestSheet', () {
    final complete = find.byKey(const ValueKey('profile-drink-complete'));

    Future<void> openSheet(
      WidgetTester tester, {
      required Set<DrinkInterest> initial,
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
      Set<DrinkInterest>? saved;
      await openSheet(
        tester,
        initial: const {DrinkInterest.wine},
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
      expect(saved, {DrinkInterest.whisky});
      expect(find.byType(DrinkInterestSheet), findsNothing);
    });

    testWidgets('a failed save keeps the sheet open and says so', (
      tester,
    ) async {
      await openSheet(
        tester,
        initial: const {DrinkInterest.wine},
        onSave: (_) async => false,
      );
      await tester.tap(complete);
      await tester.pumpAndSettle();
      expect(find.byType(DrinkInterestSheet), findsOneWidget);
      expect(find.text('관심 주종을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    });

    testWidgets('disables an empty selection', (tester) async {
      var saves = 0;
      await openSheet(
        tester,
        initial: const {DrinkInterest.wine},
        onSave: (_) async {
          saves++;
          return true;
        },
      );
      await tester.tap(find.byKey(const ValueKey('profile-drink-와인')));
      await tester.pump();
      await tester.tap(complete);
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(find.byType(DrinkInterestSheet), findsOneWidget);
    });
  });
}
