import 'dart:async';

import 'package:soolgyul/src/core/errors/connection_failure.dart';
import 'package:soolgyul/src/core/catalog/drink_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/profile/presentation/profile_screens.dart';
import 'package:soolgyul/src/widgets/app_button.dart';
import 'package:soolgyul/src/widgets/app_chip.dart';

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
  group('NicknameEditPopup', () {
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
            onPressed: () => showNicknameEditPopup(
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

    testWidgets('a name that cannot be saved turns 저장 off, with no line '
        'under the field; a name that can has none either', (tester) async {
      final saved = <String>[];
      await openSheet(tester, (nickname) async {
        saved.add(nickname);
        return true;
      });
      bool canSave() => tester.widget<AppButton>(save).onPressed != null;
      final buttons = tester.getRect(save);
      final top = tester.getRect(find.byType(NicknameEditPopup)).top;
      expect(feedback, findsNothing);
      expect(find.text('사용 가능한 닉네임이에요.'), findsNothing);
      expect(canSave(), isTrue);

      for (final name in const ['', '술', 'a', '술ㆍ결']) {
        await tester.enterText(field, name);
        await tester.pumpAndSettle();
        expect(canSave(), isFalse, reason: name);
        expect(feedback, findsNothing, reason: name);
        await tester.tap(save);
        await tester.pump();
        expect(saved, isEmpty, reason: name);
      }
      // Nothing came or went under the field: the popup stood still.
      expect(tester.getRect(save), buttons);
      expect(tester.getRect(find.byType(NicknameEditPopup)).top, top);
      for (final gone in const [
        '닉네임을 입력해 주세요.',
        '2자 이상으로 입력해 주세요.',
        '12자 이내로 입력해 주세요.',
      ]) {
        expect(find.text(gone), findsNothing);
      }

      await tester.enterText(field, '술결');
      await tester.pump();
      expect(canSave(), isTrue);
      expect(feedback, findsNothing);
    });

    testWidgets('완료 on the keyboard over a name a vowel\'s dot was left in '
        'says why; over one too short it says nothing', (tester) async {
      final saved = <String>[];
      await openSheet(tester, (nickname) async {
        saved.add(nickname);
        return true;
      });
      final buttons = tester.getRect(save);

      await tester.enterText(field, '술');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(feedback, findsNothing);

      await tester.enterText(field, '술ㆍ결');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(feedbackText(tester), '한글, 영문, 숫자만 사용할 수 있어요.');
      expect(saved, isEmpty);
      // The line makes its room upward; the buttons stay where they were.
      expect(tester.getRect(save), buttons);

      // The next key takes the line away.
      await tester.enterText(field, '술결이');
      await tester.pumpAndSettle();
      expect(feedback, findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(saved, ['술결이']);
    });

    testWidgets('a space or a mark does not go in, typed or pasted; the '
        'dots a vowel is typed through do', (tester) async {
      await openSheet(tester, (_) async => true);
      expect(find.text('술결에서 사용할 닉네임을 입력해주세요.'), findsOneWidget);
      String text() => tester.widget<EditableText>(field).controller.text;

      await tester.enterText(field, '술 결!');
      await tester.pump();
      expect(text(), '술결');
      expect(feedback, findsNothing);

      await tester.enterText(field, 'a_b-c.d@1 2😀');
      await tester.pump();
      expect(text(), 'abcd12');

      // ㅅ, then a dot and ㅣ make 서: the dots stay until the vowel forms.
      for (final dot in const [
        '\u318D',
        '\u119E',
        '\u11A2',
        '\u00B7',
        '\u2025',
      ]) {
        await tester.enterText(field, 'ㅅ$dot');
        await tester.pump();
        expect(text(), 'ㅅ$dot', reason: dot.runes.first.toRadixString(16));
      }

      // A paste goes through the same filter.
      await tester.enterText(field, '');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, Object?>{'text': '술 결! 2026 #한잔'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester
          .state<EditableTextState>(field)
          .pasteText(SelectionChangedCause.toolbar);
      await tester.pump();
      expect(text(), '술결2026한잔');
    });

    testWidgets('the popup, its field and its buttons are a little less '
        'round', (tester) async {
      await openSheet(tester, (_) async => true);
      final card = tester.widget<Material>(
        find
            .ancestor(
              of: find.byType(NicknameEditPopup),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(
        (card.shape! as RoundedRectangleBorder).borderRadius,
        const BorderRadius.all(Radius.circular(18)),
      );
      final border =
          tester
                  .widget<TextField>(find.byType(TextField))
                  .decoration!
                  .enabledBorder!
              as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(8));
      final button = tester.widget<Material>(
        find.descendant(of: save, matching: find.byType(Material)).first,
      );
      final shape = button.shape as RoundedRectangleBorder?;
      expect(
        shape?.borderRadius ?? button.borderRadius,
        BorderRadius.circular(8),
      );
    });

    testWidgets('the popup rests over the keyboard, and the page under it '
        'stays where it was', (tester) async {
      await openSheet(tester, (_) async => true);
      final popup = find.byType(NicknameEditPopup);
      final opener = tester.getRect(find.text('open'));
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      // With no keyboard it rests at the bottom, clear of both sides.
      expect(tester.getRect(popup).bottom, lessThan(screen.height));
      expect(tester.getRect(popup).left, greaterThan(0));
      expect(tester.getRect(popup).right, lessThan(screen.width));

      const keyboard = 300.0;
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboard * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final overKeyboard = tester.getRect(popup);
      expect(overKeyboard.bottom, lessThan(screen.height - keyboard));
      expect(overKeyboard.bottom, greaterThan(screen.height - keyboard - 24));
      expect(tester.getRect(find.text('open')), opener);

      // The keyboard going away does not move it.
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.getRect(popup), overKeyboard);
    });

    testWidgets('the field has no clear mark and no count, takes twelve '
        'letters at most, and 취소 closes without saving', (tester) async {
      final saved = <String>[];
      await openSheet(tester, (nickname) async {
        saved.add(nickname);
        return true;
      });
      expect(find.byTooltip('입력 내용 삭제'), findsNothing);
      expect(find.textContaining('/ 12'), findsNothing);
      await tester.enterText(field, '가나다라마바사아자차카타파하');
      await tester.pump();
      expect(tester.widget<EditableText>(field).controller.text, hasLength(12));

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.byType(NicknameEditPopup), findsNothing);
      expect(saved, isEmpty);
    });

    testWidgets('saves a valid nickname and closes', (tester) async {
      final saved = <String>[];
      await openSheet(tester, (nickname) async {
        saved.add(nickname);
        return true;
      });
      await tester.enterText(field, 'Soolgyul12');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved, <String>['Soolgyul12']);
      expect(find.byType(NicknameEditPopup), findsNothing);
    });

    testWidgets('a failed save keeps the sheet open with the message', (
      tester,
    ) async {
      await openSheet(tester, (_) async => false);
      await tester.enterText(field, '새닉네임');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(NicknameEditPopup), findsOneWidget);
      expect(feedbackText(tester), '저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
    });

    testWidgets('a save that throws says what it failed with: the connection '
        'as one, anything else in the sheet\'s own line', (tester) async {
      Object failure = ConnectionFailure('no route');
      await openSheet(tester, (_) async => throw failure);
      await tester.enterText(field, '새닉네임');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(NicknameEditPopup), findsOneWidget);
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
        expect(find.byType(NicknameEditPopup), findsNothing);
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
      // One line under the name, and no second one.
      expect(find.text('관심 있는 주종들을 선택해주세요.'), findsOneWidget);
      expect(find.textContaining('먼저 보여드릴게요'), findsNothing);

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

    testWidgets('with nothing chosen 저장 is dimmed and takes no press, and '
        'no line says why', (tester) async {
      var saves = 0;
      await openSheet(
        tester,
        initial: const {DrinkType.wine},
        onSave: (_) async {
          saves++;
          return true;
        },
      );
      double opacity() => tester
          .widget<Opacity>(
            find.ancestor(of: complete, matching: find.byType(Opacity)).first,
          )
          .opacity;
      final place = tester.getRect(complete).center;
      bool off() => tester
          .widget<IgnorePointer>(
            find
                .ancestor(of: complete, matching: find.byType(IgnorePointer))
                .first,
          )
          .ignoring;
      expect(opacity(), 1);
      expect(off(), isFalse);

      await tester.tap(find.byKey(const ValueKey('profile-drink-와인')));
      await tester.pump();
      expect(opacity(), lessThan(1));
      expect(off(), isTrue);
      expect(find.textContaining('하나 이상'), findsNothing);
      expect(
        find.byKey(const ValueKey('profile-drink-feedback')),
        findsNothing,
      );
      // It stays where it was, on the title's line.
      expect(tester.getRect(complete).center, place);
      await tester.tapAt(place);
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(find.byType(DrinkInterestSheet), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('profile-drink-위스키')));
      await tester.pump();
      expect(opacity(), 1);
    });

    testWidgets('저장 is a chip at the right end of the title\'s line, and '
        'takes one press while a save is on its way', (tester) async {
      final answer = Completer<bool>();
      var saves = 0;
      await openSheet(
        tester,
        initial: const {DrinkType.wine},
        onSave: (_) {
          saves++;
          return answer.future;
        },
      );
      final title = find.text('관심 주종 설정');
      final grid = find.byKey(const ValueKey('profile-drink-grid'));
      expect(tester.widget(complete), isA<AppChip>());
      expect(
        find.descendant(of: complete, matching: find.text('저장')),
        findsOneWidget,
      );
      expect(tester.getCenter(complete).dy, tester.getCenter(title).dy);
      expect(tester.getRect(complete).right, tester.getRect(grid).right);
      expect(
        tester.getRect(complete).bottom,
        lessThan(tester.getRect(grid).top),
      );
      // No button under the choices any more.
      expect(find.byType(AppButton), findsNothing);

      final place = tester.getRect(complete).center;
      await tester.tapAt(place);
      await tester.pump();
      await tester.tapAt(place);
      await tester.pump();
      expect(saves, 1);
      answer.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(DrinkInterestSheet), findsNothing);
    });
  });
}
