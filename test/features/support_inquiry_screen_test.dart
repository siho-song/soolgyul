import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
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

Future<void> pump(WidgetTester tester, FakeInquiries gateway) async {
  tester.view.physicalSize = const Size(411, 1200);
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
      await tester.tap(submit);
      expect(gateway.submissions, hasLength(1));
      expect(find.text('문의 보내는 중…'), findsOneWidget);
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
      expect(find.text('문의가 접수됐어요. 남겨주신 이메일로 답변드릴게요.'), findsOneWidget);
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
      await tester.tap(find.byKey(const ValueKey('support-inquiry-images')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('첨부 이미지 선택 해제'));
      await tester.pumpAndSettle();
      expect(find.text('0/5'), findsOneWidget);
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(gateway.submissions.last.id, isNot(firstId));
    },
  );
}
