import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/catalog/drink_type.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/design/app_tokens.dart';
import 'package:soolgyul/src/features/profile/presentation/profile_screens.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/widgets/app_icon_button.dart';
import 'package:soolgyul/src/widgets/app_list_row.dart';
import 'package:soolgyul/src/widgets/main_tab_title.dart';

import '../support/app_test_harness.dart';

// The 내 정보 tab: its top (the tab's name, the nickname, the account's
// email), and the rows of its three sections.

Widget _page({String? email}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SafeArea(
      child: ProfileScreen(
        nickname: '민지',
        email: email,
        interests: const <DrinkType>{},
        onNavigate: (_) {},
        onSaveNickname: (_) async => true,
        onSaveInterests: (_) async => true,
      ),
    ),
  ),
);

void main() {
  setUp(() {});

  Future<void> pump(WidgetTester tester, {String? email}) async {
    tester.view.physicalSize = const Size(402, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_page(email: email));
    await tester.pumpAndSettle();
  }

  final picture = find.byKey(const ValueKey<String>('profile-hero-background'));
  final nickname = find.byKey(const ValueKey<String>('profile-nickname'));
  final email = find.byKey(const ValueKey<String>('profile-email'));

  testWidgets('the top is the picture across the page, then the nickname '
      'and the email at the left, with no title and no slogan', (tester) async {
    await pump(tester, email: 'minji@example.com');
    expect(find.text('내 정보'), findsNothing);
    expect(find.byType(MainTabTitle), findsNothing);
    expect(tester.getTopLeft(picture), Offset.zero);
    expect(tester.getSize(picture).width, 402);
    expect(tester.widget<Text>(nickname).data, '민지');
    expect(tester.widget<Text>(email).data, 'minji@example.com');
    expect(tester.widget<Text>(email).maxLines, 1);
    expect(tester.widget<Text>(email).overflow, TextOverflow.ellipsis);

    // The picture, then the name, then the email, each under the last.
    expect(
      tester.getTopLeft(nickname).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(picture).dy),
    );
    expect(
      tester.getTopLeft(email).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(nickname).dy),
    );
    // One left edge, the page's own: the first part starts there too.
    final lefts = {
      for (final line in [nickname, email]) tester.getTopLeft(line).dx,
      tester.getTopLeft(find.text('계정')).dx,
    };
    expect(lefts, hasLength(1));
    expect(find.textContaining('한 잔씩'), findsNothing);
    // No pencil by the name: it is changed from the 계정 rows.
    expect(
      find.descendant(
        of: find.byType(ProfileHero),
        matching: find.byType(AppIconButton),
      ),
      findsNothing,
    );
  });

  testWidgets('계정 holds 닉네임 변경 and 관심 주종, each a row that opens its '
      'sheet; the drinks of interest are not drawn on the tab', (tester) async {
    await pump(tester);
    final account = find.byType(ProfileMenuList).first;
    expect(
      tester.getTopLeft(account).dy,
      greaterThan(tester.getTopLeft(find.text('계정')).dy),
    );
    expect(
      tester.getTopLeft(account).dy,
      lessThan(tester.getTopLeft(find.text('내 서랍')).dy),
    );
    expect(
      tester
          .widgetList<AppListRow>(
            find.descendant(of: account, matching: find.byType(AppListRow)),
          )
          .map((row) => row.title),
      ['닉네임 변경', '관심 주종'],
    );
    expect(find.textContaining('관심 주종이 없어요'), findsNothing);
    expect(find.byType(Wrap), findsNothing);

    await tester.tap(find.text('닉네임 변경'));
    await tester.pumpAndSettle();
    expect(find.byType(NicknameEditPopup), findsOneWidget);
    Navigator.of(tester.element(find.byType(NicknameEditPopup))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('관심 주종'));
    await tester.pumpAndSettle();
    expect(find.text('관심 주종 설정'), findsOneWidget);
  });

  testWidgets('an account without an email has no email line, and no '
      'placeholder in its place', (tester) async {
    await pump(tester);
    expect(email, findsNothing);
    expect(nickname, findsOneWidget);
    // The first part follows the nickname.
    final card = find.text('계정');
    expect(
      tester.getTopLeft(card).dy,
      greaterThan(tester.getBottomLeft(nickname).dy),
    );
    expect(
      find.descendant(
        of: find.byType(ProfileHero),
        matching: find.byType(Text),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the names of the three parts are small, and a line parts the '
      'rows of a part from the icon\'s left edge to the arrow\'s right', (
    tester,
  ) async {
    await pump(tester);
    for (final name in ['계정', '내 서랍', '설정 및 지원']) {
      expect(tester.widget<Text>(find.text(name)).style?.fontSize, 14);
    }
    final lists = find.byType(ProfileMenuList);
    final lines = find.descendant(
      of: lists,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == AppColors.borderStrong,
      ),
    );
    // One fewer than the rows of each part: 1, 1 and 2.
    expect(lines, findsNWidgets(4));
    final icon = find.descendant(of: lists, matching: find.byType(Image)).first;
    for (final line in lines.evaluate()) {
      // The lines are one constant widget, so each is found by its place.
      final rect = tester.getRect(
        find.byElementPredicate((element) => element == line),
      );
      expect(rect.left, tester.getTopLeft(icon).dx);
      expect(rect.right, tester.getRect(lists.first).right);
    }
  });

  testWidgets('the rows of 계정, 내 서랍 and 설정 및 지원 lead with the icon alone, '
      'no disc behind it, in one column at the row\'s own height, and show '
      'no count', (tester) async {
    await pump(tester);
    final panels = find.byType(ProfileMenuList);
    expect(panels, findsNWidgets(3));
    expect(
      find.descendant(of: panels, matching: find.byType(CircleAvatar)),
      findsNothing,
    );
    final icons = find.descendant(of: panels, matching: find.byType(Image));
    // Two rows of 계정, two of 내 서랍 and three of 설정 및 지원, each with
    // a picture of its own.
    expect(icons, findsNWidgets(7));
    expect(
      tester
          .widgetList<Image>(icons)
          .map((icon) => (icon.image as AssetImage).assetName)
          .toSet(),
      hasLength(7),
    );
    for (final icon in tester.widgetList<Image>(icons)) {
      expect((icon.width, icon.height), (28, 28));
    }
    expect({
      for (final element in icons.evaluate())
        tester.getTopLeft(find.byWidget(element.widget)).dx,
    }, hasLength(1));
    // A row is its icon, its name and the arrow: one text each, no number
    // and no placeholder for one.
    final rows = find.descendant(of: panels, matching: find.byType(AppListRow));
    expect(rows, findsNWidgets(7));
    expect(
      find.descendant(of: panels, matching: find.byType(Text)),
      findsNWidgets(7),
    );
    expect(find.text('—'), findsNothing);
    // 내 서랍 keeps bottles and terms; posts and cards are not kept there.
    expect(find.text('저장한 이야기'), findsNothing);
    expect(find.text('보관한 술결 카드'), findsNothing);
    for (final name in ['저장한 술', '나의 용어 사전']) {
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(AppListRow),
      );
      expect(tester.getSize(row).height, AppSizes.menuRowHeight, reason: name);
    }
    // The rows keep their height, and the last one is 문의하기.
    for (final name in ['약관 및 정책', '문의하기']) {
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(AppListRow),
      );
      expect(tester.getSize(row).height, AppSizes.menuRowHeight, reason: name);
    }
    expect(find.text('고객지원 및 문의'), findsNothing);
    // Nothing on the tab loads, so nothing on it can fail to.
    expect(find.text('기록을 불러오지 못했어요.'), findsNothing);
    expect(find.text('다시 시도'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('in the app the picture reaches under the status bar and the '
      'lines stay below it, with the signed-in account\'s email', (
    tester,
  ) async {
    final auth = FakeSocialAuthGateway(signedInEmail: 'member@example.com');
    addTearDown(auth.close);
    await pumpAppAtRoute(
      tester,
      AppRoute.profile,
      defaultAppTestViewport,
      auth,
    );
    tester.view.padding = const FakeViewPadding(top: 47);
    tester.view.viewPadding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(picture).dy, 0);
    // No profile was read here, so there is no name and no line kept for
    // one: the email is the first line under the picture.
    expect(nickname, findsNothing);
    expect(tester.getTopLeft(email).dy, greaterThanOrEqualTo(47));
    expect(
      tester.getTopLeft(email).dy - tester.getBottomLeft(picture).dy,
      lessThan(AppSpacing.md),
    );
    expect(tester.widget<Text>(email).data, 'member@example.com');
  });
}
