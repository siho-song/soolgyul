import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary_provider.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_verdict.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_search_screen.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_badge.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_paper_card.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';
import '../support/design_taste_card.dart';
import '../support/fake_search.dart';
import '../support/test_catalog.dart';

final _drink = TestCatalog.dryWhiteWine;

/// A reader without cards until [cards] is set; then the bottle is a star.
class _Fit implements TasteFitGateway {
  bool cards = false;

  @override
  Future<TasteFitResponse> judge(List<String> productIds) async =>
      TasteFitResponse(
        hasCards: cards,
        verdicts: <String, TasteFitVerdict>{
          if (cards)
            _drink.id: TasteFitVerdict(
              productId: _drink.id,
              badge: TasteFitBadge.star,
              headline: '딱 맞는 PICK',
              sentence: '좋아하신 산뜻한 산미를 갖고 있어요.',
            ),
        },
      );
}

/// Saves every record at once, and the reader has a card from then on.
class _Cards implements TasteCardGateway {
  _Cards(this.fit);

  final _Fit fit;

  @override
  bool get isAuthenticated => true;

  @override
  Future<TasteCardCreateOutcome> create(
    CreateTasteCardResultRequest request,
  ) async {
    fit.cards = true;
    return TasteCardFinalOutcome(
      TasteCardResult(
        resultId: '20000000-0000-4000-8000-000000000001',
        recordId: '30000000-0000-4000-8000-000000000001',
        snapshotRef: designTasteCard.snapshotRef,
        ownership: TasteCardOwnership.saved,
        viewData: designTasteCard,
      ),
    );
  }

  @override
  Future<TasteCardResult> convert(AnonymousTasteCardConversionRequest r) =>
      throw UnimplementedError();

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) =>
      throw UnimplementedError();

  @override
  Future<void> deleteOwnedResult(String resultId) => throw UnimplementedError();
}

void main() {
  testWidgets('a first record made from a bottle\'s fit page brings its '
      'verdict, there and in the search behind', (tester) async {
    final fit = _Fit();
    final router = AppRouter(
      initialRoute: AppRoute.tasteFitSearch,
      child: AppFlow(
        initialRoute: AppRoute.tasteFitSearch,
        catalogSearchGateway: const TestCatalogGateway(),
        tasteFitGateway: fit,
        tasteCardGateway: _Cards(fit),
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
      ),
    );
    addTearDown(router.dispose);
    useTestViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileSummaryLoaderProvider.overrideWithValue(
            () async => ProfileSummary(
              cardCount: fit.cards ? 1 : 0,
              savedArticleCount: 0,
              likedCardCount: 0,
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerDelegate: router,
          routeInformationParser: AppRouteInformationParser(
            fallback: AppRoute.tasteFitSearch,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await typeSearch(tester, '테스트 드라이');
    await tester.pumpAndSettle();
    expect(find.text(tasteFitNoCardsHint), findsOneWidget);
    await tester.tap(find.text(_drink.displayName));
    await tester.pumpAndSettle();
    expect(router.currentRoute, AppRoute.tasteFitDetail);
    expect(find.text(tasteFitNoCardsHint), findsOneWidget);

    final record = find.byKey(
      const ValueKey<String>('taste-fit-record-button'),
    );
    await tester.ensureVisible(record);
    await tester.tap(record);
    await tester.pumpAndSettle();
    await tapSensoryOption(tester, 'revisit:wantAgain');
    await tapSensoryOption(tester, 'sensory-next');
    await completeSensoryQuestionsWithOneAnswer(tester);
    expect(find.byType(TasteCardScreen), findsOneWidget);

    // Back from the card to the bottle the record began on.
    router.pop();
    await tester.pumpAndSettle();
    expect(router.currentRoute, AppRoute.tasteFitDetail);
    expect(find.text(tasteFitNoCardsHint), findsNothing);
    expect(find.text('딱 맞는 PICK'), findsOneWidget);
    expect(find.byType(TasteFitPaperCard), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(router.currentRoute, AppRoute.tasteFitSearch);
    expect(find.text(tasteFitNoCardsHint), findsNothing);
    expect(find.byType(TasteFitRowBadge), findsOneWidget);
  });
}
