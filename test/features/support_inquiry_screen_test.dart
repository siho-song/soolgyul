import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soolgyul/src/widgets/app_button.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';
import 'package:soolgyul/src/features/profile/data/support_inquiry_gateway.dart';
import 'package:soolgyul/src/features/profile/presentation/profile_screens.dart';

class FakeInquiries implements SupportInquiryGateway {
  final submissions = <SupportInquiryDraft>[];
  Completer<void>? pending;
  bool fail = false;
  @override
  Future<void> submit(SupportInquiryDraft draft) async {
    submissions.add(draft);
    if (pending != null) await pending!.future;
    if (fail) throw const SupportInquiryException('전송 실패 테스트');
  }
}

Finder field(String name) => find.descendant(
  of: find.byKey(ValueKey('support-inquiry-$name')),
  matching: find.byType(EditableText),
);
final submit = find.byKey(const ValueKey('support-inquiry-submit'));

Future<void> pump(
  WidgetTester tester,
  FakeInquiries gateway, {
  Size size = const Size(411, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SupportInquiryScreen(
          gateway: gateway,
          pickImages: () async => [XFile('one.png')],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The form as the app shows it, opened from 고객지원 및 문의.
Future<AppRouter> pumpInApp(WidgetTester tester, FakeInquiries gateway) async {
  final router = AppRouter(
    initialRoute: AppRoute.supportInquiry,
    child: AppFlow(
      initialRoute: AppRoute.supportInquiry,
      supportInquiryGateway: gateway,
    ),
  );
  addTearDown(router.dispose);
  tester.view.physicalSize = const Size(411, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerDelegate: router,
        routeInformationParser: AppRouteInformationParser(
          fallback: AppRoute.supportInquiry,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

final headerBack = find.byTooltip('이전 화면으로 이동');
const leaveQuestion = '작성 중인 문의를 지울까요?';

bool fullyOnScreen(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  final screen = Offset.zero & tester.view.physicalSize;
  return screen.contains(rect.topLeft) &&
      screen.contains(rect.bottomRight - const Offset(1, 1));
}

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(field('email'), 'user@example.com');
  await tester.enterText(field('content'), '실제 문의 내용');
  await tester.pump();
}

void main() {
  testWidgets('the form leaves retention and privacy terms to the policy', (
    tester,
  ) async {
    await pump(tester, FakeInquiries());
    expect(find.textContaining('6개월'), findsNothing);
    expect(find.textContaining('24시간'), findsNothing);
    expect(find.textContaining('개인정보'), findsNothing);
    expect(find.textContaining('위해서만 사용'), findsNothing);
    expect(
      find.byKey(const ValueKey('support-inquiry-submit')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('actual app route passes the inquiry gateway to the form', (
    tester,
  ) async {
    final gateway = FakeInquiries();
    final router = AppRouter(
      initialRoute: AppRoute.supportInquiry,
      child: AppFlow(
        initialRoute: AppRoute.supportInquiry,
        supportInquiryGateway: gateway,
      ),
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(411, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerDelegate: router,
          routeInformationParser: AppRouteInformationParser(
            fallback: AppRoute.supportInquiry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await fill(tester);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(gateway.submissions, hasLength(1));
    expect(gateway.submissions.single.content, '실제 문의 내용');
  });

  testWidgets('invalid input does not call the gateway', (tester) async {
    final gateway = FakeInquiries();
    await pump(tester, gateway);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(gateway.submissions, isEmpty);
    expect(find.text('문의 내용을 입력해 주세요.'), findsOneWidget);
  });

  testWidgets(
    'submission waits for server, blocks repeat taps and clears only on success',
    (tester) async {
      final gateway = FakeInquiries()..pending = Completer<void>();
      await pump(tester, gateway);
      await fill(tester);
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      await tester.tap(submit, warnIfMissed: false);
      expect(gateway.submissions, hasLength(1));
      expect(tester.widget<AppButton>(submit).isLoading, isTrue);
      expect(
        tester.widget<EditableText>(field('content')).controller.text,
        '실제 문의 내용',
      );
      gateway.pending!.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(field('content')).controller.text,
        isEmpty,
      );
      expect(find.text('소중한 문의가 접수되었어요. 확인 후 이메일로 답변해 드릴게요.'), findsOneWidget);
    },
  );

  testWidgets('failure retains content, selected files and the retry ID', (
    tester,
  ) async {
    final gateway = FakeInquiries()..fail = true;
    await pump(tester, gateway);
    await fill(tester);
    final picker = find.byKey(const ValueKey('support-inquiry-images'));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('전송 실패 테스트'), findsOneWidget);
    expect(find.text('1/5'), findsOneWidget);
    expect(
      tester.widget<EditableText>(field('content')).controller.text,
      '실제 문의 내용',
    );
    final first = gateway.submissions.single;
    gateway.fail = false;
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(gateway.submissions.last.id, first.id);
    expect(gateway.submissions.last.images.single.path, 'one.png');
    expect(find.text('0/5'), findsOneWidget);
  });

  testWidgets(
    'editing a failed inquiry changes the request ID and attachments can be removed',
    (tester) async {
      final gateway = FakeInquiries()..fail = true;
      await pump(tester, gateway);
      await fill(tester);
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      final firstId = gateway.submissions.single.id;
      await tester.enterText(field('content'), '수정된 문의 내용');
      final add = find.byKey(const ValueKey('support-inquiry-images'));
      await tester.tap(add);
      await tester.pumpAndSettle();
      // A second pick adds to the photos already attached, each shown.
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('2/5'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('support-inquiry-image-1')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('support-inquiry-image-0')),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1/5'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('0/5'), findsOneWidget);
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(gateway.submissions.last.id, isNot(firstId));
    },
  );

  testWidgets('the header back and the system back ask before a written '
      'inquiry is left', (tester) async {
    final router = await pumpInApp(tester, FakeInquiries());
    await fill(tester);

    await tester.tap(headerBack);
    await tester.pumpAndSettle();
    expect(find.text(leaveQuestion), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('support-inquiry-stay')));
    await tester.pumpAndSettle();
    expect(router.currentRoute, AppRoute.supportInquiry);
    expect(
      tester.widget<EditableText>(field('content')).controller.text,
      '실제 문의 내용',
    );

    // The system back asks too, and a second one only closes the question.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(leaveQuestion), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(leaveQuestion), findsNothing);
    expect(router.currentRoute, AppRoute.supportInquiry);

    await tester.tap(headerBack);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('support-inquiry-leave')));
    await tester.pumpAndSettle();
    expect(router.currentRoute, AppRoute.supportCenter);
  });

  testWidgets('an email alone is left without a question', (tester) async {
    final router = await pumpInApp(tester, FakeInquiries());
    await tester.enterText(field('email'), 'user@example.com');
    await tester.pump();
    await tester.tap(headerBack);
    await tester.pumpAndSettle();
    expect(find.text(leaveQuestion), findsNothing);
    expect(router.currentRoute, AppRoute.supportCenter);
  });

  testWidgets('a photo alone counts as writing to lose', (tester) async {
    await pump(tester, FakeInquiries());
    RoutePopDisposition leaving() => ModalRoute.of(
      tester.element(find.byType(SupportInquiryScreen)),
    )!.popDisposition;
    expect(leaving(), isNot(RoutePopDisposition.doNotPop));

    final picker = find.byKey(const ValueKey('support-inquiry-images'));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(leaving(), RoutePopDisposition.doNotPop);
  });

  testWidgets('leaving while an inquiry is sent asks, and staying shows the '
      'result', (tester) async {
    final gateway = FakeInquiries()..pending = Completer<void>();
    final router = await pumpInApp(tester, gateway);
    await fill(tester);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    // The button's spinner turns while the inquiry is on its way, so the
    // frames never settle: the popup is given its time to open and close.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('문의를 보내고 있어요'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('support-inquiry-stay')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('문의를 보내고 있어요'), findsNothing);
    expect(router.currentRoute, AppRoute.supportInquiry);

    gateway.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('소중한 문의가 접수되었어요. 확인 후 이메일로 답변해 드릴게요.'), findsOneWidget);

    // Sent and cleared: nothing is left to ask about.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.currentRoute, AppRoute.supportCenter);
  });

  testWidgets(
    'an iPhone swipe back is off while there is writing to lose',
    (tester) async {
      final router = await pumpInApp(tester, FakeInquiries());
      Future<void> swipeBack() async {
        await tester.dragFrom(const Offset(4, 600), const Offset(360, 0));
        await tester.pumpAndSettle();
      }

      await fill(tester);
      await swipeBack();
      expect(router.currentRoute, AppRoute.supportInquiry);
      expect(find.text(leaveQuestion), findsNothing);

      await tester.enterText(field('content'), '');
      await tester.pump();
      await swipeBack();
      expect(router.currentRoute, AppRoute.supportCenter);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('dragging the page puts the keyboard away', (tester) async {
    await pump(tester, FakeInquiries(), size: const Size(411, 500));
    await tester.showKeyboard(field('content'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.drag(
      find.byKey(const ValueKey('support-inquiry-form')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('a failed check takes the cursor to the first field with an '
      'error, and shows the error', (tester) async {
    final gateway = FakeInquiries();
    await pump(tester, gateway, size: const Size(411, 420));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    const emailError = '답변받을 이메일을 입력해 주세요.';
    expect(
      tester.widget<EditableText>(field('email')).focusNode.hasFocus,
      isTrue,
    );
    expect(fullyOnScreen(tester, field('email')), isTrue);
    // The hint says the same; the error is the line under the field.
    expect(find.text(emailError), findsNWidgets(2));
    expect(fullyOnScreen(tester, find.text(emailError).last), isTrue);

    // With the email right, the next field with an error takes it.
    await tester.enterText(field('email'), 'user@example.com');
    await tester.pumpAndSettle();
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(field('content')).focusNode.hasFocus,
      isTrue,
    );
    expect(fullyOnScreen(tester, find.text('문의 내용을 입력해 주세요.')), isTrue);
    expect(gateway.submissions, isEmpty);
  });

  testWidgets("a photo's remove mark takes a tap anywhere on its corner", (
    tester,
  ) async {
    await pump(tester, FakeInquiries());
    final picker = find.byKey(const ValueKey('support-inquiry-images'));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.text('1/5'), findsOneWidget);

    // The far end of a 44pt corner; the mark itself is 22pt wide.
    final photo = tester.getRect(
      find.byKey(const ValueKey('support-inquiry-image-0')),
    );
    await tester.tapAt(photo.topRight + const Offset(-42, 42));
    await tester.pumpAndSettle();
    expect(find.text('0/5'), findsOneWidget);
  });
}
