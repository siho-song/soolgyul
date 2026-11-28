import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:soolgyul/src/core/errors/connection_failure.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/profile/presentation/saved_drinks_screen.dart';
import 'package:soolgyul/src/features/taste_fit/data/saved_drinks_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/supabase_saved_drinks_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_verdict.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_detail_screen.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_badge.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_save_button.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';
import 'package:soolgyul/src/widgets/app_filter_chip.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';

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

// A rosé: the catalog files it under wine, the app under no wine sheet.
const _rose = CatalogDrink(
  id: 'whispering-angel',
  displayName: '위스퍼링 엔젤 로제',
  category: DrinkCategory.other,
  categoryKey: 'wine',
  styleKey: 'rose_wine',
);
const _makgeolli = CatalogDrink(
  id: 'boksoondoga',
  displayName: '복순도가 손막걸리',
  category: DrinkCategory.koreanTraditional,
  categoryKey: 'korean_traditional',
);
// A bottle of a 주종 this version of the app does not list.
const _unfiled = CatalogDrink(
  id: 'unfiled',
  displayName: '이름 모를 술',
  category: DrinkCategory.other,
);

/// The bottles on the list, top to bottom.
List<String> _listed(WidgetTester tester) {
  final list = find.byKey(const ValueKey<String>('saved-drinks-list'));
  if (list.evaluate().isEmpty) return const <String>[];
  final names = <(double, String)>[
    for (final drink in const <CatalogDrink>[
      _balvenie,
      _dassai,
      _rose,
      _makgeolli,
      _unfiled,
    ])
      for (final row
          in find
              .descendant(of: list, matching: find.text(drink.displayName))
              .evaluate())
        (tester.getTopLeft(find.byWidget(row.widget)).dy, drink.displayName),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return <String>[for (final (_, name) in names) name];
}

Future<void> _chooseChip(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey<String>('saved-drinks-filter-$key')));
  await tester.pumpAndSettle();
}

/// The labels of the chips drawn as chosen.
List<String> _chosenChips(WidgetTester tester) => <String>[
  for (final chip in tester.widgetList<AppFilterChip>(
    find.byType(AppFilterChip),
  ))
    if (chip.selected) chip.label,
];

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

  /// What a failed save or unsave fails with.
  Object writeFailure = StateError('offline');

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
    if (failWrite) throw writeFailure;
    badges[drinkId] = badge;
    drinks.insert(0, shown!);
  }

  @override
  Future<void> unsave(String drinkId) async {
    if (failWrite) throw writeFailure;
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

/// Answers each bottle with the face in [badges], which the test may
/// change, and keeps the bottles asked in each call.
class _FacesFit implements TasteFitGateway {
  _FacesFit(this.badges);

  Map<String, TasteFitBadge> badges;
  bool hasCards = true;
  bool fail = false;
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<TasteFitResponse> judge(List<String> productIds) async {
    calls.add(productIds);
    if (fail) throw const TasteFitGatewayException();
    return TasteFitResponse(
      hasCards: hasCards,
      verdicts: <String, TasteFitVerdict>{
        for (final id in productIds)
          if (badges[id] case final badge?)
            id: TasteFitVerdict(productId: id, badge: badge, headline: ''),
      },
    );
  }
}

/// The face on the row of the bottle named [name]; null when it has none.
TasteFitBadge? _faceOf(WidgetTester tester, String name) {
  final row = find.ancestor(
    of: find.text(name),
    matching: find.byType(InkWell),
  );
  final face = find.descendant(
    of: row.first,
    matching: find.byType(TasteFitRowBadge),
  );
  return face.evaluate().isEmpty
      ? null
      : tester.widget<TasteFitRowBadge>(face).badge;
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
      // The reader is told where the bottle went; cancelling says nothing
      // and takes that notice down.
      const kept = '저장한 술에 담았어요. 내 정보에서 다시 볼 수 있어요.';
      expect(find.text(kept), findsOneWidget);

      await tester.tap(_heart);
      await tester.pumpAndSettle();
      expect(find.text(kept), findsNothing);
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

        // The same save over a dead connection says the connection.
        gateway.writeFailure = ConnectionFailure('no route');
        await tester.tap(_heart);
        await tester.pumpAndSettle();
        expect(
          find.text('네트워크 연결이 불안정해요. 연결을 확인한 뒤 다시 시도해 주세요.'),
          findsOneWidget,
        );
        expect(find.textContaining('저장을 변경하지'), findsNothing);
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

    testWidgets('each row shows its face left of the chevron', (tester) async {
      final fit = _FacesFit(<String, TasteFitBadge>{
        _dassai.id: TasteFitBadge.star,
        _balvenie.id: TasteFitBadge.caution,
      });
      await pumpTestScreen(
        tester,
        SavedDrinksScreen(
          gateway: _Saved(const <CatalogDrink>[_dassai, _balvenie]),
          tasteFitGateway: fit,
          onOpen: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(_faceOf(tester, _dassai.displayName), TasteFitBadge.star);
      expect(_faceOf(tester, _balvenie.displayName), TasteFitBadge.caution);
      final row = find.ancestor(
        of: find.text(_dassai.displayName),
        matching: find.byType(InkWell),
      );
      final face = find.descendant(
        of: row.first,
        matching: find.byType(TasteFitRowBadge),
      );
      final chevron = find.descendant(
        of: row.first,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.icon == AppIconAsset.next,
        ),
      );
      expect(
        tester.getTopRight(face).dx,
        lessThan(tester.getTopLeft(chevron).dx),
      );
    });

    testWidgets('the faces follow the cards after a new record', (
      tester,
    ) async {
      final saved = _Saved(const <CatalogDrink>[_balvenie]);
      final fit = _FacesFit(<String, TasteFitBadge>{
        _balvenie.id: TasteFitBadge.star,
      });
      Widget screen(int recordsRevision) => SavedDrinksScreen(
        gateway: saved,
        tasteFitGateway: fit,
        recordsRevision: recordsRevision,
        onOpen: (_) {},
      );
      await pumpTestScreen(tester, screen(0));
      await tester.pumpAndSettle();
      expect(_faceOf(tester, _balvenie.displayName), TasteFitBadge.star);

      fit.badges = <String, TasteFitBadge>{_balvenie.id: TasteFitBadge.neutral};
      await pumpTestScreen(tester, screen(1));
      await tester.pumpAndSettle();
      expect(_faceOf(tester, _balvenie.displayName), TasteFitBadge.neutral);
      // The list itself was not asked for again.
      expect(saved.offsets, <int>[0]);
    });

    testWidgets('a page is handed to the fit call whole', (tester) async {
      final fit = _FacesFit(const <String, TasteFitBadge>{});
      await pumpTestScreen(
        tester,
        SavedDrinksScreen(
          gateway: _Saved(<CatalogDrink>[
            for (var index = 0; index < 25; index++)
              CatalogDrink(
                id: 'drink-$index',
                displayName: '테스트 술 $index',
                category: DrinkCategory.whisky,
              ),
          ]),
          tasteFitGateway: fit,
          onOpen: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      expect(fit.calls.map((ids) => ids.length), <int>[25]);
    });

    testWidgets('rows stay without faces when there is nothing to show', (
      tester,
    ) async {
      for (final fit in <_FacesFit>[
        // No cards to judge by.
        _FacesFit(<String, TasteFitBadge>{_balvenie.id: TasteFitBadge.star})
          ..hasCards = false,
        // A kind the reader never recorded.
        _FacesFit(<String, TasteFitBadge>{_balvenie.id: TasteFitBadge.noInfo}),
        // The fit call failed.
        _FacesFit(const <String, TasteFitBadge>{})..fail = true,
      ]) {
        await pumpTestScreen(
          tester,
          SavedDrinksScreen(
            key: UniqueKey(),
            gateway: _Saved(const <CatalogDrink>[_balvenie]),
            tasteFitGateway: fit,
            onOpen: (_) {},
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(_balvenie.displayName), findsOneWidget);
        expect(find.byType(TasteFitRowBadge), findsNothing);
      }
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
        // The list's own scroll, not the chips' sideways one above it.
        find.ancestor(
          of: find.byKey(const ValueKey<String>('saved-drinks-list')),
          matching: find.byType(Scrollable),
        ),
        const Offset(0, -400),
        maxIteration: 30,
      );
      await tester.pumpAndSettle();
      expect(gateway.offsets, <int>[0, 20]);
    });

    testWidgets('the chips keep the bottles of one 주종, one chip at a time', (
      tester,
    ) async {
      await pumpTestScreen(
        tester,
        SavedDrinksScreen(
          gateway: _Saved(const <CatalogDrink>[
            _dassai,
            _balvenie,
            _rose,
            _makgeolli,
            _unfiled,
          ]),
          onOpen: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      // 전체 first, then each 주종 in the app's one order.
      expect(
        tester.widgetList<AppFilterChip>(find.byType(AppFilterChip)).map((
          chip,
        ) {
          return (chip.label, chip.selected);
        }),
        <(String, bool)>[
          ('전체', true),
          ('와인', false),
          ('위스키', false),
          ('사케', false),
          ('전통주', false),
        ],
      );
      expect(_listed(tester), <String>[
        _dassai.displayName,
        _balvenie.displayName,
        _rose.displayName,
        _makgeolli.displayName,
        _unfiled.displayName,
      ]);

      await _chooseChip(tester, 'whisky');
      expect(_listed(tester), <String>[_balvenie.displayName]);
      expect(_chosenChips(tester), <String>['위스키']);
      // A rosé is a wine, though no wine question sheet is its own.
      await _chooseChip(tester, 'wine');
      expect(_listed(tester), <String>[_rose.displayName]);
      expect(_chosenChips(tester), <String>['와인']);
      await _chooseChip(tester, 'korean_traditional');
      expect(_listed(tester), <String>[_makgeolli.displayName]);
      await _chooseChip(tester, 'sake');
      expect(_listed(tester), <String>[_dassai.displayName]);
      // A bottle of no 주종 the app lists shows under 전체 only.
      await _chooseChip(tester, 'all');
      expect(_listed(tester), hasLength(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a chip with no bottle says what an empty list says', (
      tester,
    ) async {
      const empty = '저장한 술이 아직 없어요.\n내게 맞는 술 찾기에서 하트를 눌러 담아 보세요.';
      await pumpTestScreen(
        tester,
        SavedDrinksScreen(
          gateway: _Saved(const <CatalogDrink>[_balvenie]),
          onOpen: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(empty), findsNothing);

      await _chooseChip(tester, 'sake');
      expect(find.text(empty), findsOneWidget);
      expect(_listed(tester), isEmpty);
      // The chips stay, to choose another.
      await _chooseChip(tester, 'whisky');
      expect(find.text(empty), findsNothing);
      expect(_listed(tester), <String>[_balvenie.displayName]);

      // Nothing saved at all: the same words under the same chips.
      await pumpTestScreen(
        tester,
        SavedDrinksScreen(key: UniqueKey(), gateway: _Saved(), onOpen: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(find.text(empty), findsOneWidget);
      expect(find.byType(AppFilterChip), findsNWidgets(5));
    });

    testWidgets('a chosen 주종 is looked for on the pages not yet asked for', (
      tester,
    ) async {
      final gateway = _Saved(<CatalogDrink>[
        for (var index = 0; index < 45; index++)
          CatalogDrink(
            id: 'drink-$index',
            displayName: '테스트 술 $index',
            category: DrinkCategory.whisky,
          ),
        _dassai,
      ])..pageSize = 20;
      await pumpTestScreen(
        tester,
        SavedDrinksScreen(gateway: gateway, onOpen: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(gateway.offsets, <int>[0]);

      // The one sake was saved first, so it is on the last page.
      await _chooseChip(tester, 'sake');
      expect(gateway.offsets, <int>[0, 20, 40]);
      expect(_listed(tester), <String>[_dassai.displayName]);
    });

    testWidgets('a page that fails under a chosen 주종 can be asked for again', (
      tester,
    ) async {
      final gateway = _Saved(<CatalogDrink>[
        for (var index = 0; index < 25; index++)
          CatalogDrink(
            id: 'drink-$index',
            displayName: '테스트 술 $index',
            category: DrinkCategory.whisky,
          ),
        _dassai,
      ])..pageSize = 20;
      await pumpTestScreen(
        tester,
        SavedDrinksScreen(gateway: gateway, onOpen: (_) {}),
      );
      await tester.pumpAndSettle();

      gateway.failFetch = true;
      await _chooseChip(tester, 'sake');
      // Not "nothing saved": its bottle may be on the page that failed.
      expect(find.textContaining('저장한 술이 아직 없어요.'), findsNothing);
      expect(find.text('저장한 술을 불러오지 못했어요'), findsOneWidget);

      gateway.failFetch = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(_listed(tester), <String>[_dassai.displayName]);
    });

    testWidgets('a bottle taken out leaves the list under its chip too', (
      tester,
    ) async {
      final gateway = _Saved(const <CatalogDrink>[_dassai, _balvenie]);
      Widget screen(int revision) => SavedDrinksScreen(
        gateway: gateway,
        revision: revision,
        onOpen: (_) {},
      );
      await pumpTestScreen(tester, screen(0));
      await tester.pumpAndSettle();
      await _chooseChip(tester, 'whisky');
      expect(_listed(tester), <String>[_balvenie.displayName]);

      // Its heart was taken off on the fit page.
      await gateway.unsave(_balvenie.id);
      await pumpTestScreen(tester, screen(1));
      await tester.pumpAndSettle();
      expect(_chosenChips(tester), <String>['위스키']);
      expect(_listed(tester), isEmpty);
      expect(find.textContaining('저장한 술이 아직 없어요.'), findsOneWidget);
    });

    testWidgets('the chips fit a narrow phone and large letters', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpTestScreen(
        tester,
        SavedDrinksScreen(
          gateway: _Saved(const <CatalogDrink>[_dassai, _balvenie]),
          onOpen: (_) {},
        ),
        viewport: const Size(360, 640),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The row scrolls sideways to its last chip.
      const last = ValueKey<String>('saved-drinks-filter-korean_traditional');
      await tester.ensureVisible(find.byKey(last));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(last));
      await tester.pumpAndSettle();
      expect(_chosenChips(tester), <String>['전통주']);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a bottle saved on its fit page shows in 저장한 술, with its count', (
    tester,
  ) async {
    final gateway = _Saved(const <CatalogDrink>[_balvenie])..shown = _balvenie;
    final router = AppRouter(
      initialRoute: AppRoute.profile,
      child: AppFlow(
        initialRoute: AppRoute.profile,
        savedDrinksGateway: gateway,
        tasteFitGateway: _Fit(),
      ),
    );
    addTearDown(router.dispose);
    useTestViewport(tester, const Size(411, 1100));
    await tester.pumpWidget(
      ProviderScope(
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
  });
}
