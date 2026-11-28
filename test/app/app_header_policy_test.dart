import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app_header_policy.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/widgets/app_top_bar.dart';

Future<void> _pumpHeader(WidgetTester tester, PreferredSizeWidget? header) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(appBar: header),
      ),
    );

final _back = find.byTooltip('이전 화면으로 이동');

void main() {
  testWidgets('a finished card closes with an X; while its note is written '
      'the header shows the arrow back and 완료 instead', (tester) async {
    var closes = 0;
    var backs = 0;
    PreferredSizeWidget? header({required bool editing}) =>
        AppHeaderPolicy.build(
          route: AppRoute.onboardingResult,
          onBack: () {},
          resultOnClose: () => closes++,
          resultEditBack: editing ? () => backs++ : null,
          resultActions: <Widget>[
            if (editing) AppTopBarTextAction(label: '완료', onPressed: () {}),
          ],
        );
    await _pumpHeader(tester, header(editing: false));
    expect(find.byTooltip('닫기'), findsOneWidget);
    expect(_back, findsNothing);
    await tester.tap(find.byTooltip('닫기'));
    expect(closes, 1);

    await _pumpHeader(tester, header(editing: true));
    expect(find.byTooltip('닫기'), findsNothing);
    expect(find.text('완료'), findsOneWidget);
    await tester.tap(_back);
    expect(backs, 1);
    expect(closes, 1);
  });

  testWidgets('a new card has no way back while it is made; one that could '
      'not be made leads back', (tester) async {
    var backs = 0;
    PreferredSizeWidget? header({required bool canGoBack}) =>
        AppHeaderPolicy.build(
          route: AppRoute.onboardingResult,
          onBack: () => backs++,
          resultCanGoBack: canGoBack,
        );

    await _pumpHeader(tester, header(canGoBack: false));
    expect(_back, findsNothing);

    await _pumpHeader(tester, header(canGoBack: true));
    await tester.tap(_back);
    expect(backs, 1);
  });

  testWidgets('a post offers its Instagram link and the way back, and no '
      'bookmark', (tester) async {
    var opened = 0;
    await _pumpHeader(
      tester,
      AppHeaderPolicy.build(
        route: AppRoute.editorialArticle,
        onBack: () {},
        onEditorialInstagram: () => opened++,
      ),
    );
    expect(_back, findsOneWidget);
    expect(find.byType(AppTopBarMaterialAction), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('editorial-article-instagram')),
    );
    expect(opened, 1);
  });
}
