import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary_provider.dart';
import 'package:soolgyul/src/features/profile/presentation/saved_drinks_screen.dart';
import 'package:soolgyul/src/features/taste_fit/data/saved_drinks_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/supabase_saved_drinks_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_verdict.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_detail_screen.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_save_button.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';
import '../support/fake_supabase.dart';

const _balvenie = CatalogDrink(
  id: 'balvenie-12',
  displayName: '발베니 더블우드 12년',
  category: DrinkCategory.whisky,
  styleLabel: '싱글 몰트 위스키',
  abvPercent: 40,
);
const _dassai = CatalogDrink(
  id: 'dassai-45',
  displayName: '닷사이 준마이 다이긴죠 45',
  category: DrinkCategory.sake,
  styleLabel: '사케',
);

/// Keeps the saved bottles in a list, newest first, and what was asked.
class _Saved implements SavedDrinksGateway {
  _Saved([List<CatalogDrink> drinks = const <CatalogDrink>[]])
    : drinks = <CatalogDrink>[...drinks];

  final List<CatalogDrink> drinks;
  final Map<String, TasteFitBadge?> badges = <String, TasteFitBadge?>{};
  final List<int> offsets = <int>[];
  int pageSize = 30;
  bool failFetch = false;
  bool failWrite = false;

  /// The bottle the fit page is showing, to save by its id.
  CatalogDrink? shown;

  @override
  Future<SavedDrinksPage> fetch({int offset = 0}) async {
    offsets.add(offset);
    if (failFetch) throw StateError('offline');
    return SavedDrinksPage(
      drinks: drinks.skip(offset).take(pageSize).toList(),
      total: drinks.length,
    );
  }

  @override
  Future<bool> isSaved(String drinkId) async =>
      drinks.any((drink) => drink.id == drinkId);

  @override
  Future<void> save(String drinkId, {TasteFitBadge? badge}) async {
    if (failWrite) throw StateError('offline');
    badges[drinkId] = badge;
    drinks.insert(0, shown!);
  }

  @override
  Future<void> unsave(String drinkId) async {
    if (failWrite) throw StateError('offline');
    drinks.removeWhere((drink) => drink.id == drinkId);
  }
}

class _Fit implements TasteFitGateway {
  @override
  Future<TasteFitResponse> judge(List<String> productIds) async =>
      TasteFitResponse(
        hasCards: true,
        verdicts: <String, TasteFitVerdict>{
          for (final id in productIds)
            id: TasteFitVerdict(
              productId: id,
              badge: TasteFitBadge.star,
              headline: '딱 맞는 PICK !',
            ),
        },
      );
}

Finder get _heart =>
    find.byKey(const ValueKey<String>('taste-fit-save-button'));

void main() {
  group('SupabaseSavedDrinksGateway', () {
    late List<http.Request> requests;
    late SupabaseSavedDrinksGateway gateway;
    Object reply = const <Object?>[];

    setUp(() async {
      requests = <http.Request>[];
      final client = fakeSupabaseClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(reply),
          200,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }, userId: 'owner');
      addTearDown(client.dispose);
      await signInFake(client);
      gateway = SupabaseSavedDrinksGateway(client);
    });

    test('a page comes through the owner function as search rows', () async {
      reply = <String, Object?>{
        'total': 31,
        'drinks': <Object?>[
          <String, Object?>{
            'id': 'balvenie-12',
            'saved_at': '2026-11-12T03:00:00Z',
            'name_ko': '발베니 더블우드 12년',
            'name_en': 'Balvenie DoubleWood 12',
            'category_key': 'whisky',
            'style_key': 'single_malt',
            'style_label': '싱글 몰트 위스키',
            'abv_percent': 40,
            'media_path': 'whisky/balvenie.webp',
            'country_code': 'GB',
            'region': '스페이사이드',
          },
          // A row without a name is left out; the rest still shows.
          <String, Object?>{'id': 'broken', 'category_key': 'whisky'},
        ],
      };
      final page = await gateway.fetch(offset: 30);

      expect(page.total, 31);
      final drink = page.drinks.single;
      expect(drink.id, 'balvenie-12');
      expect(drink.displayName, '발베니 더블우드 12년');
      expect(drink.category, DrinkCategory.whisky);
      expect(drink.styleLabel, '싱글 몰트 위스키');
      expect(drink.abvPercent, 40);
      expect(drink.photoUrl, contains('whisky/balvenie.webp'));
      final call = requests.single;
      expect(call.url.path, '/rest/v1/rpc/soolgyul_my_saved_drinks');
      expect(jsonDecode(call.body), {'p_offset': 30, 'p_limit': 30});
    });

    test(
      'a save carries the badge the fit page shows, by its server name',
      () async {
        await gateway.save('balvenie-12', badge: TasteFitBadge.noInfo);
        await gateway.save('dassai-45');
        await gateway.unsave('balvenie-12');

        expect(requests.map((request) => request.url.path), [
          '/rest/v1/rpc/soolgyul_save_my_drink',
          '/rest/v1/rpc/soolgyul_save_my_drink',
          '/rest/v1/rpc/soolgyul_unsave_my_drink',
        ]);
        expect(jsonDecode(requests[0].body), {
          'p_alcohol_item_id': 'balvenie-12',
          'p_fit_badge': 'no_info',
        });
        expect(jsonDecode(requests[1].body), {
          'p_alcohol_item_id': 'dassai-45',
          'p_fit_badge': null,
        });
        expect(jsonDecode(requests[2].body), {
          'p_alcohol_item_id': 'balvenie-12',
        });
      },
    );

    test(
      'whether a bottle is saved is read from the owner\'s own rows',
      () async {
        reply = <Object?>[
          <String, Object?>{'alcohol_item_id': 'balvenie-12'},
        ];
        expect(await gateway.isSaved('balvenie-12'), isTrue);
        final query = requests.single.url;
        expect(query.path, '/rest/v1/user_saved_drinks');
        expect(query.queryParameters['user_id'], 'eq.owner');
        expect(query.queryParameters['alcohol_item_id'], 'eq.balvenie-12');

        reply = const <Object?>[];
        expect(await gateway.isSaved('dassai-45'), isFalse);
      },
    );
  });

  group('TasteFitSaveButton', () {
    Future<void> pumpButton(
      WidgetTester tester,
      _Saved gateway, {
      TasteFitBadge? badge,
      VoidCallback? onChanged,
    }) async {
      gateway.shown = _balvenie;
      await pumpTestScreen(
        tester,
        TasteFitSaveButton(
          drinkId: _balvenie.id,
          gateway: gateway,
          badge: badge,
          onChanged: onChanged,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the heart saves with the shown badge and takes out again', (
      tester,
    ) async {
      final gateway = _Saved();
      var changes = 0;
      await pumpButton(
        tester,
        gateway,
        badge: TasteFitBadge.star,
        onChanged: () => changes++,
      );
      expect(find.byTooltip('술 저장하기'), findsOneWidget);

      await tester.tap(_heart);
      await tester.pumpAndSettle();
      expect(gateway.drinks.single.id, _balvenie.id);
      expect(gateway.badges[_balvenie.id], TasteFitBadge.star);
      expect(find.byTooltip('저장 취소'), findsOneWidget);

      await tester.tap(_heart);
      await tester.pumpAndSettle();
      expect(gateway.drinks, isEmpty);
      expect(find.byTooltip('술 저장하기'), findsOneWidget);
      expect(changes, 2);
    });

    testWidgets('a saved bottle opens with a filled heart', (tester) async {
      await pumpButton(tester, _Saved(const <CatalogDrink>[_balvenie]));
      expect(find.byTooltip('저장 취소'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets(
      'a save the server refuses says so and leaves the heart empty',
      (tester) async {
        final gateway = _Saved()..failWrite = true;
        var changes = 0;
        await pumpButton(tester, gateway, onChanged: () => changes++);

        await tester.tap(_heart);
        await tester.pumpAndSettle();
        expect(find.text('저장을 변경하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
        expect(find.byTooltip('술 저장하기'), findsOneWidget);
        expect(changes, 0);
      },
    );
  });

  group('SavedDrinksScreen', () {
    testWidgets('lists the saved bottles and opens the one tapped', (
      tester,
    ) async {
      final opened = <CatalogDrink>[];
      await pumpTestScreen(
        tester,
        SavedDrinksScreen(
          gateway: _Saved(const <CatalogDrink>[_dassai, _balvenie]),
          onOpen: opened.add,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('닷사이 준마이 다이긴죠 45')).dy,
        lessThan(tester.getTopLeft(find.text('발베니 더블우드 12년')).dy),
      );
      await tester.tap(find.text('발베니 더블우드 12년'));
      expect(opened.single.id, _balvenie.id);
    });

    testWidgets('an empty list says where the heart is', (tester) async {
      await pumpTestScreen(
        tester,
        SavedDrinksScreen(gateway: _Saved(), onOpen: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('저장한 술이 아직 없어요.'), findsOneWidget);
    });

    testWidgets('a list that did not load can be asked for again', (
      tester,
    ) async {
      final gateway = _Saved(const <CatalogDrink>[_balvenie])..failFetch = true;
      await pumpTestScreen(
        tester,
        SavedDrinksScreen(gateway: gateway, onOpen: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(find.text('저장한 술을 불러오지 못했어요'), findsOneWidget);

      gateway.failFetch = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('발베니 더블우드 12년'), findsOneWidget);
    });

    testWidgets('the next page is asked for at the end of the list', (
      tester,
    ) async {
      final gateway = _Saved(<CatalogDrink>[
        for (var index = 0; index < 25; index++)
          CatalogDrink(
            id: 'drink-$index',
            displayName: '테스트 술 $index',
            category: DrinkCategory.whisky,
          ),
      ])..pageSize = 20;
      await pumpTestScreen(
        tester,
        SavedDrinksScreen(gateway: gateway, onOpen: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(gateway.offsets, <int>[0]);

      await tester.dragUntilVisible(
        find.text('테스트 술 24'),
        find.byType(Scrollable).first,
        const Offset(0, -400),
        maxIteration: 30,
      );
      await tester.pumpAndSettle();
      expect(gateway.offsets, <int>[0, 20]);
    });
  });

  testWidgets('a bottle saved on its fit page shows in 저장한 술, with its count', (
    tester,
  ) async {
    final gateway = _Saved(const <CatalogDrink>[_balvenie])..shown = _balvenie;
    var summaryLoads = 0;
    final router = AppRouter(
      initialRoute: AppRoute.profile,
      child: AppFlow(
        initialRoute: AppRoute.profile,
        savedDrinksGateway: gateway,
        tasteFitGateway: _Fit(),
      ),
    );
    Future<ProfileSummary> summary() async {
      summaryLoads++;
      return ProfileSummary(
        cardCount: 2,
        savedArticleCount: 0,
        likedCardCount: 0,
        savedDrinkCount: gateway.drinks.length,
      );
    }

    addTearDown(router.dispose);
    useTestViewport(tester, const Size(411, 1100));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileSummaryLoaderProvider.overrideWithValue(summary)],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerDelegate: router,
          routeInformationParser: AppRouteInformationParser(
            fallback: AppRoute.profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('저장한 술'));
    await tester.pumpAndSettle();
    expect(router.currentRoute, AppRoute.savedDrinks);

    // A row opens the bottle's fit page, which asks for the verdict itself.
    await tester.tap(find.text('발베니 더블우드 12년'));
    await tester.pumpAndSettle();
    expect(router.currentRoute, AppRoute.tasteFitDetail);
    expect(find.byType(TasteFitDetailScreen), findsOneWidget);
    expect(find.byTooltip('저장 취소'), findsOneWidget);

    await tester.tap(_heart);
    await tester.pumpAndSettle();
    expect(gateway.drinks, isEmpty);
    // Saved again, the verdict the page came to show goes with it.
    await tester.tap(_heart);
    await tester.pumpAndSettle();
    expect(gateway.badges[_balvenie.id], TasteFitBadge.star);
    await tester.tap(_heart);
    await tester.pumpAndSettle();

    router.pop();
    await tester.pumpAndSettle();
    expect(router.currentRoute, AppRoute.savedDrinks);
    expect(find.textContaining('저장한 술이 아직 없어요.'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(summaryLoads, greaterThan(1));
  });
}
