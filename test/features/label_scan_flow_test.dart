import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_layout.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_text_recognizer.dart';
import 'package:soolgyul/src/features/taste_fit/data/saved_drinks_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_verdict.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/label_camera_screen.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/label_results_screen.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/label_scan_flow.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_search_screen.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/label_reading_screen.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/label_shots_review_screen.dart';

import '../support/app_test_harness.dart';
import '../support/fake_search.dart';

const _ardbeg = CatalogDrink(
  id: 'ardbeg-10',
  displayName: '아드벡 10년',
  category: DrinkCategory.whisky,
  styleLabel: '싱글 몰트 위스키',
  abvPercent: 46,
);

const _glenfiddich = CatalogDrink(
  id: 'glenfiddich-12',
  displayName: '글렌피딕 12년',
  category: DrinkCategory.whisky,
  styleLabel: '싱글 몰트 위스키',
  abvPercent: 40,
);

const _jameson = CatalogDrink(
  id: 'jameson',
  displayName: '제임슨',
  category: DrinkCategory.whisky,
  styleLabel: '블렌디드 위스키',
  abvPercent: 40,
);

const _montes = CatalogDrink(
  id: 'montes',
  displayName: '몬테스 알파',
  category: DrinkCategory.redWine,
  styleLabel: '레드 와인',
  abvPercent: 14,
);

const _byName = <String, CatalogDrink>{
  '아드벡': _ardbeg,
  '글렌피딕': _glenfiddich,
  '제임슨': _jameson,
  '몬테스': _montes,
};

BottleCut _ardbegCut(double left) =>
    bottleCut(left, const <String>['아드벡', '10년']);
BottleCut _glenfiddichCut(double left) =>
    bottleCut(left, const <String>['글렌피딕', '12년']);
BottleCut _jamesonCut(double left) => bottleCut(left, const <String>['제임슨']);
BottleCut _montesCut(double left) =>
    bottleCut(left, const <String>['몬테스', '알파']);

/// Finds each drink by the word of its name a query holds, and is sure of
/// whatever bottle it is shown: the judge names the first candidate.
class _Catalog with SearchManyByOne implements LabelPhotoJudge {
  _Catalog({this.fails = 0});

  /// How many searches fail before they answer.
  int fails;
  int judged = 0;

  /// The drinks the judge answers of only when its completer is completed.
  final Map<String, Completer<void>> slow = <String, Completer<void>>{};

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    if (fails > 0) {
      fails -= 1;
      throw const CatalogSearchException();
    }
    return <CatalogDrink>[
      for (final MapEntry(:key, :value) in _byName.entries)
        if (query.contains(key)) value,
    ];
  }

  @override
  Future<String?> pickByPhoto(
    Uint8List photo,
    List<String> candidateIds, {
    required bool appSure,
  }) async {
    judged += 1;
    await slow[candidateIds.firstOrNull]?.future;
    return candidateIds.firstOrNull;
  }
}

/// The bottles of each photo by its path; a photo not listed shows none
/// and reads nothing whole.
class _Photos implements LabelTextRecognizer, LabelBottleReader {
  _Photos(this.bottles);

  final Map<String, List<BottleCut>> bottles;
  final List<String> read = <String>[];

  @override
  Future<List<BottleBox>> findBottles(String imagePath) async => <BottleBox>[
    for (final cut in bottles[imagePath] ?? const <BottleCut>[]) cut.box,
  ];

  @override
  Future<List<ReadLine>> readBottle(String imagePath, BottleBox bottle) async {
    read.add(imagePath);
    return bottles[imagePath]!
        .firstWhere((cut) => identical(cut.box, bottle))
        .lines;
  }

  @override
  Future<List<ReadLine>> recognizeLines(String imagePath) async =>
      const <ReadLine>[];

  @override
  Future<Uint8List> bottlePhoto(String imagePath, [BottleBox? bottle]) async =>
      Uint8List.fromList(const <int>[0xFF, 0xD8]);
}

class _Saved implements SavedDrinksGateway {
  _Saved(this.ids);

  final Set<String> ids;

  @override
  Future<bool> isSaved(String drinkId) async => ids.contains(drinkId);

  @override
  Future<SavedDrinksPage> fetch({int offset = 0}) => throw UnimplementedError();

  @override
  Future<void> save(String drinkId, {TasteFitBadge? badge}) =>
      throw UnimplementedError();

  @override
  Future<void> unsave(String drinkId) => throw UnimplementedError();
}

class _FailingFit implements TasteFitGateway {
  int fails = 1;

  @override
  Future<TasteFitResponse> judge(List<String> productIds) async {
    if (fails > 0) {
      fails -= 1;
      throw const TasteFitGatewayException();
    }
    return _fit(<String, TasteFitBadge>{_ardbeg.id: TasteFitBadge.star});
  }
}

TasteFitResponse _fit(Map<String, TasteFitBadge> badges, {bool cards = true}) =>
    TasteFitResponse(
      hasCards: cards,
      verdicts: <String, TasteFitVerdict>{
        for (final MapEntry(:key, :value) in badges.entries)
          key: TasteFitVerdict(productId: key, badge: value, headline: 'h'),
      },
    );

final _whiskyFit = _fit(<String, TasteFitBadge>{
  _ardbeg.id: TasteFitBadge.caution,
  _glenfiddich.id: TasteFitBadge.star,
  _jameson.id: TasteFitBadge.neutral,
  _montes.id: TasteFitBadge.noInfo,
});

final _flowKey = GlobalKey<LabelScanFlowState>();

/// A page with a button that opens the flow over it, as the search does.
Future<List<TasteFitSelection>> _open(
  WidgetTester tester, {
  required Map<String, List<BottleCut>> photos,
  CatalogSearchGateway? catalog,
  TasteFitGateway? fit,
  SavedDrinksGateway? saved,
  FakeDiscoveryEvents? events,
  LabelTextRecognizer? recognizer,
}) async {
  final selected = <TasteFitSelection>[];
  useTestViewport(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => LabelScanFlow(
                    key: _flowKey,
                    catalogSearchGateway: catalog ?? _Catalog(),
                    recognizer: recognizer ?? _Photos(photos),
                    tasteFitGateway: fit ?? FakeTasteFit(_whiskyFit),
                    savedDrinks: saved,
                    discoveryEvents: events,
                    onSelect: selected.add,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return selected;
}

Future<void> _shoot(
  WidgetTester tester,
  String path, {
  Rect shown = const Rect.fromLTWH(0, 0, 1, 1),
}) async {
  _flowKey.currentState!.addShot(LabelShot(XFile(path), shown: shown));
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey<String>(key));

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

double _top(WidgetTester tester, CatalogDrink drink) =>
    tester.getTopLeft(find.text(drink.displayName)).dy;

void main() {
  testWidgets('photos are read together and their drinks listed best fit '
      'first, the ones without a face apart', (tester) async {
    final events = FakeDiscoveryEvents();
    final selected = await _open(
      tester,
      photos: <String, List<BottleCut>>{
        'a.jpg': <BottleCut>[_ardbegCut(.05)],
        'b.jpg': <BottleCut>[_glenfiddichCut(.05)],
        'c.jpg': <BottleCut>[_montesCut(.05)],
        'd.jpg': <BottleCut>[_jamesonCut(.05)],
      },
      saved: _Saved(<String>{_jameson.id}),
      events: events,
    );
    for (final photo in <String>['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg']) {
      await _shoot(tester, photo);
    }
    expect(
      find.descendant(of: _key('label-camera-shots'), matching: find.text('4')),
      findsOneWidget,
    );

    await _tap(tester, 'label-camera-results');

    expect(find.byType(LabelResultsScreen), findsOneWidget);
    expect(find.text(labelResultsRankTitle), findsOneWidget);
    expect(find.text(labelResultsFoundNote(4)), findsOneWidget);
    // Smile, plain, frown; then the wine nobody has a record to judge by.
    expect(_top(tester, _glenfiddich), lessThan(_top(tester, _jameson)));
    expect(_top(tester, _jameson), lessThan(_top(tester, _ardbeg)));
    final note = tester.getTopLeft(find.text(labelResultsUnjudgedNote)).dy;
    expect(_top(tester, _ardbeg), lessThan(note));
    expect(note, lessThan(_top(tester, _montes)));
    final ranked = _key('label-results-ranked');
    for (final place in <String>['1', '2', '3']) {
      expect(
        find.descendant(of: ranked, matching: find.text(place)),
        findsOneWidget,
      );
    }
    expect(_key('label-find-saved'), findsOneWidget);
    expect(
      events.events.where((event) => event.startsWith('label_match')).length,
      4,
    );

    await _tap(tester, 'label-find:${_glenfiddich.id}');
    expect(selected.single.drink, _glenfiddich);
    expect(selected.single.verdict?.badge, TasteFitBadge.star);
    expect(selected.single.judged, isTrue);
    expect(events.events.sublist(4), <String>[
      'label_pick taste_fit ${_glenfiddich.id} null',
      'fit_view taste_fit ${_glenfiddich.id} null',
    ]);
  });

  testWidgets('a member with no records sees the finds unranked under the '
      'reason', (tester) async {
    await _open(
      tester,
      photos: <String, List<BottleCut>>{
        'a.jpg': <BottleCut>[_ardbegCut(.05)],
        'b.jpg': <BottleCut>[_glenfiddichCut(.05)],
      },
      fit: FakeTasteFit(_fit(const <String, TasteFitBadge>{}, cards: false)),
    );
    await _shoot(tester, 'a.jpg');
    await _shoot(tester, 'b.jpg');
    await _tap(tester, 'label-camera-results');

    expect(find.text(labelResultsFoundTitle), findsOneWidget);
    expect(find.text(labelResultsRankTitle), findsNothing);
    expect(find.text(labelResultsUnjudgedNote), findsOneWidget);
    expect(_key('label-results-ranked'), findsNothing);
  });

  testWidgets('photos that show no drink say so, with 더 찍기 and 검색 above', (
    tester,
  ) async {
    await _open(tester, photos: const <String, List<BottleCut>>{});
    await _shoot(tester, 'empty.jpg');
    await _tap(tester, 'label-camera-results');

    expect(find.text(labelResultsNoneTitle), findsOneWidget);
    expect(_key('label-results-more'), findsOneWidget);
    expect(_key('label-results-search'), findsOneWidget);
  });

  testWidgets('a photo is read and searched as it is taken, and judged '
      'once the list is asked for', (tester) async {
    final photos = _Photos(<String, List<BottleCut>>{
      'a.jpg': <BottleCut>[_ardbegCut(.05)],
      'b.jpg': <BottleCut>[_glenfiddichCut(.05)],
    });
    final catalog = _Catalog();
    await _open(
      tester,
      photos: photos.bottles,
      recognizer: photos,
      catalog: catalog,
    );
    await _shoot(tester, 'a.jpg');
    await _shoot(tester, 'b.jpg');
    expect(photos.read, <String>['a.jpg', 'b.jpg']);
    expect(catalog.judged, 0, reason: 'no photo leaves the phone yet');

    await _tap(tester, 'label-camera-results');
    expect(photos.read, <String>['a.jpg', 'b.jpg'], reason: 'not read again');
    expect(catalog.judged, 2);
    expect(find.text(_ardbeg.displayName), findsOneWidget);
    expect(find.text(_glenfiddich.displayName), findsOneWidget);
  });

  testWidgets('a photo answered late does not hold the list: it opens with '
      'the others, says a bottle is still checked, and takes the late drink '
      'in at its place', (tester) async {
    final catalog = _Catalog()..slow[_glenfiddich.id] = Completer<void>();
    await _open(
      tester,
      photos: <String, List<BottleCut>>{
        'a.jpg': <BottleCut>[_ardbegCut(.05)],
        'b.jpg': <BottleCut>[_glenfiddichCut(.05)],
        'c.jpg': <BottleCut>[_jamesonCut(.05)],
      },
      catalog: catalog,
    );
    await _shoot(tester, 'a.jpg');
    await _shoot(tester, 'b.jpg');
    await _shoot(tester, 'c.jpg');
    await tester.tap(_key('label-camera-results'));
    await tester.pump(labelListWait - const Duration(milliseconds: 100));
    expect(find.byType(LabelReadingScreen), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.byType(LabelResultsScreen), findsOneWidget);
    expect(find.text(labelResultsFoundNote(2)), findsOneWidget);
    expect(find.text(labelResultsCheckingNote(1)), findsOneWidget);
    expect(find.text(_glenfiddich.displayName), findsNothing);

    catalog.slow[_glenfiddich.id]!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text(labelResultsFoundNote(3)), findsOneWidget);
    expect(_key('label-results-checking'), findsNothing);
    expect(
      _top(tester, _glenfiddich),
      lessThan(_top(tester, _jameson)),
      reason: 'the smile ranks first',
    );
  });

  testWidgets('with no photo answered yet the list says it is checking, and '
      'an answer that has not come in time is no longer waited for', (
    tester,
  ) async {
    final catalog = _Catalog()..slow[_ardbeg.id] = Completer<void>();
    await _open(
      tester,
      photos: <String, List<BottleCut>>{
        'a.jpg': <BottleCut>[_ardbegCut(.05)],
      },
      catalog: catalog,
    );
    await _shoot(tester, 'a.jpg');
    await tester.tap(_key('label-camera-results'));
    await tester.pump(labelListWait);
    await tester.pump();
    expect(find.text(labelResultsCheckingTitle), findsOneWidget);
    expect(find.text(labelResultsNoneTitle), findsNothing);

    await tester.pump(labelLateWait);
    expect(find.text(labelResultsCheckingTitle), findsNothing);
    expect(find.text(labelResultsNoneTitle), findsOneWidget);

    catalog.slow[_ardbeg.id]!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text(_ardbeg.displayName), findsNothing);
  });

  testWidgets('더 찍기 while a bottle is still checked keeps waiting for it', (
    tester,
  ) async {
    final catalog = _Catalog()..slow[_glenfiddich.id] = Completer<void>();
    await _open(
      tester,
      photos: <String, List<BottleCut>>{
        'a.jpg': <BottleCut>[_ardbegCut(.05)],
        'b.jpg': <BottleCut>[_glenfiddichCut(.05)],
        'c.jpg': <BottleCut>[_jamesonCut(.05)],
      },
      catalog: catalog,
    );
    await _shoot(tester, 'a.jpg');
    await _shoot(tester, 'b.jpg');
    await tester.tap(_key('label-camera-results'));
    await tester.pump(labelListWait);
    await tester.pump();
    await tester.tap(_key('label-results-more'));
    await tester.pump();
    await _shoot(tester, 'c.jpg');
    await tester.tap(_key('label-camera-close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(_key('label-leave'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(labelResultsCheckingNote(1)), findsOneWidget);

    catalog.slow[_glenfiddich.id]!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text(_glenfiddich.displayName), findsOneWidget);
    expect(find.text(_jameson.displayName), findsNothing);
  });

  testWidgets('a search that failed as the photo was taken is made again '
      'when the list is asked for', (tester) async {
    await _open(
      tester,
      photos: <String, List<BottleCut>>{
        'a.jpg': <BottleCut>[_ardbegCut(.05)],
      },
      catalog: _Catalog(fails: 1),
    );
    await _shoot(tester, 'a.jpg');
    await _tap(tester, 'label-camera-results');
    expect(find.text(labelReadingFailedTitle), findsNothing);
    expect(find.text(_ardbeg.displayName), findsOneWidget);
  });

  testWidgets('a photo taken out on its small ✕ is not listed, and the last '
      'one gone returns to the camera', (tester) async {
    final photos = _Photos(<String, List<BottleCut>>{
      'a.jpg': <BottleCut>[_ardbegCut(.05)],
      'b.jpg': <BottleCut>[_glenfiddichCut(.05)],
    });
    final catalog = _Catalog();
    await _open(
      tester,
      photos: photos.bottles,
      recognizer: photos,
      catalog: catalog,
    );
    await _shoot(tester, 'a.jpg');
    await _shoot(tester, 'b.jpg');

    await _tap(tester, 'label-camera-shots');
    expect(find.byType(LabelShotsReviewScreen), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    await _tap(tester, 'label-shot-delete-0');
    expect(find.text('1 / 1'), findsOneWidget);
    await _tap(tester, 'label-shots-back');
    expect(find.byType(LabelShotsReviewScreen), findsNothing);

    await _tap(tester, 'label-camera-results');
    expect(catalog.judged, 1, reason: 'the photo taken out is never sent');
    expect(find.text(_glenfiddich.displayName), findsOneWidget);
    expect(find.text(_ardbeg.displayName), findsNothing);

    await _tap(tester, 'label-results-more');
    await _shoot(tester, 'a.jpg');
    await _tap(tester, 'label-camera-shots');
    await _tap(tester, 'label-shot-delete-0');
    expect(find.byType(LabelShotsReviewScreen), findsNothing);
    expect(_key('label-camera-shots'), findsNothing);
  });

  testWidgets('더 찍기 opens the camera with an empty stack and a way back, and '
      'adds what the new photos show once', (tester) async {
    final photos = _Photos(<String, List<BottleCut>>{
      'a.jpg': <BottleCut>[_ardbegCut(.05)],
      'b.jpg': <BottleCut>[_glenfiddichCut(.05)],
      'c.jpg': <BottleCut>[_glenfiddichCut(.05)],
      'd.jpg': <BottleCut>[_jamesonCut(.05)],
    });
    await _open(tester, photos: photos.bottles, recognizer: photos);
    await _shoot(tester, 'a.jpg');
    await _shoot(tester, 'b.jpg');
    await _tap(tester, 'label-camera-results');
    expect(find.text(labelResultsFoundNote(2)), findsOneWidget);

    await _tap(tester, 'label-results-more');
    expect(_key('label-camera-shots'), findsNothing);
    // The way back with nothing taken asks nothing.
    await _tap(tester, 'label-camera-close');
    expect(find.text(labelResultsFoundNote(2)), findsOneWidget);

    await _tap(tester, 'label-results-more');
    photos.read.clear();
    await _shoot(tester, 'c.jpg');
    await _shoot(tester, 'd.jpg');
    await _tap(tester, 'label-camera-results');
    // Only the new photos are read.
    expect(photos.read.toSet(), <String>{'c.jpg', 'd.jpg'});
    expect(find.text(labelResultsFoundNote(3)), findsOneWidget);
    expect(find.text(_glenfiddich.displayName), findsOneWidget);
    expect(_top(tester, _glenfiddich), lessThan(_top(tester, _jameson)));
    expect(_top(tester, _jameson), lessThan(_top(tester, _ardbeg)));
  });

  testWidgets('the way back from 더 찍기 with photos taken asks once and drops '
      'them', (tester) async {
    await _open(
      tester,
      photos: <String, List<BottleCut>>{
        'a.jpg': <BottleCut>[_ardbegCut(.05)],
        'b.jpg': <BottleCut>[_jamesonCut(.05)],
      },
    );
    await _shoot(tester, 'a.jpg');
    await _tap(tester, 'label-camera-results');
    await _tap(tester, 'label-results-more');
    await _shoot(tester, 'b.jpg');

    await _tap(tester, 'label-camera-close');
    expect(find.text(labelCameraLeaveTitle), findsOneWidget);
    await tester.tap(find.text(labelCameraStayLabel));
    await tester.pumpAndSettle();
    expect(_key('label-camera-shots'), findsOneWidget);

    await _tap(tester, 'label-camera-close');
    await _tap(tester, 'label-leave');
    expect(find.text(labelResultsFoundNote(1)), findsOneWidget);
    await _tap(tester, 'label-results-more');
    expect(_key('label-camera-shots'), findsNothing);
  });

  testWidgets('closing the camera asks only when photos were taken, and '
      'closing the finds always asks', (tester) async {
    await _open(
      tester,
      photos: <String, List<BottleCut>>{
        'a.jpg': <BottleCut>[_ardbegCut(.05)],
      },
    );
    await _tap(tester, 'label-camera-close');
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(LabelScanFlow), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _shoot(tester, 'a.jpg');
    await _tap(tester, 'label-camera-close');
    expect(find.text(labelCameraLeaveBody), findsOneWidget);
    await tester.tap(find.text(labelCameraStayLabel));
    await tester.pumpAndSettle();

    await _tap(tester, 'label-camera-results');
    await _tap(tester, 'label-results-close');
    expect(find.text(labelResultsLeaveTitle), findsOneWidget);
    await tester.tap(find.text(labelResultsStayLabel));
    await tester.pumpAndSettle();
    expect(find.byType(LabelResultsScreen), findsOneWidget);

    // The system back is the ✕.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(labelResultsLeaveTitle), findsOneWidget);
    await _tap(tester, 'label-leave');
    expect(find.byType(LabelScanFlow), findsNothing);
  });

  testWidgets('a reading that failed says so, keeps the photos and reads '
      'them again', (tester) async {
    await _open(
      tester,
      photos: <String, List<BottleCut>>{
        'a.jpg': <BottleCut>[_ardbegCut(.05)],
      },
      // The search made as the photo is taken fails, and so does the one
      // made again when the list is asked for.
      catalog: _Catalog(fails: 2),
    );
    await _shoot(tester, 'a.jpg');
    await _tap(tester, 'label-camera-results');

    expect(find.byType(LabelReadingScreen), findsOneWidget);
    expect(find.text(labelReadingFailedTitle), findsOneWidget);
    // Back to the camera, the photo still in its stack.
    await tester.tap(find.byTooltip('이전 화면으로 이동'));
    await tester.pumpAndSettle();
    expect(_key('label-camera-shots'), findsOneWidget);

    await _tap(tester, 'label-camera-results');
    expect(find.text(_ardbeg.displayName), findsOneWidget);
  });

  testWidgets('verdicts that did not come are asked for again without '
      'reading the photos twice', (tester) async {
    final photos = _Photos(<String, List<BottleCut>>{
      'a.jpg': <BottleCut>[_ardbegCut(.05)],
    });
    await _open(
      tester,
      photos: photos.bottles,
      recognizer: photos,
      fit: _FailingFit(),
    );
    await _shoot(tester, 'a.jpg');
    await _tap(tester, 'label-camera-results');
    expect(find.text(labelReadingFailedTitle), findsOneWidget);

    await _tap(tester, 'label-reading-retry');
    expect(find.text(_ardbeg.displayName), findsOneWidget);
    expect(photos.read, <String>['a.jpg']);
  });

  testWidgets('a photo of several bottles says so above the shutter, and '
      'only the one nearest the middle is read', (tester) async {
    final photos = _Photos(<String, List<BottleCut>>{
      'a.jpg': <BottleCut>[
        _ardbegCut(.0),
        _glenfiddichCut(.35),
        _jamesonCut(.7),
      ],
      'b.jpg': <BottleCut>[_montesCut(.35)],
    });
    await _open(tester, photos: photos.bottles, recognizer: photos);
    await _shoot(tester, 'b.jpg');
    // The test's phone has no camera to draw the line over, so the line
    // is read where the camera is handed it.
    LabelCameraScreen camera() =>
        tester.widget<LabelCameraScreen>(find.byType(LabelCameraScreen));
    expect(camera().notice, isNull);
    await _shoot(tester, 'a.jpg');
    expect(camera().notice, labelCameraSeveralHint);

    await _tap(tester, 'label-camera-results');
    expect(photos.read, <String>['b.jpg', 'a.jpg']);
    expect(find.text(labelResultsFoundNote(2)), findsOneWidget);
    expect(find.text(_glenfiddich.displayName), findsOneWidget);
    expect(find.text(_ardbeg.displayName), findsNothing);
    expect(find.text(_jameson.displayName), findsNothing);
  });

  testWidgets('a bottle outside what the viewfinder showed is not read, '
      'however near the middle', (tester) async {
    final photos = _Photos(<String, List<BottleCut>>{
      'a.jpg': <BottleCut>[
        (
          box: const BottleBox(left: 0, top: .3, right: .1, bottom: .7),
          lines: labelLines(const <String>['아드벡', '10년']),
        ),
        (
          box: const BottleBox(left: .4, top: 0, right: .6, bottom: .2),
          lines: labelLines(const <String>['제임슨']),
        ),
      ],
    });
    await _open(tester, photos: photos.bottles, recognizer: photos);
    await _shoot(tester, 'a.jpg', shown: const Rect.fromLTRB(0, .125, 1, .875));
    expect(
      tester.widget<LabelCameraScreen>(find.byType(LabelCameraScreen)).notice,
      isNull,
      reason: 'one bottle was in the picture',
    );
    await _tap(tester, 'label-camera-results');

    expect(find.text(_ardbeg.displayName), findsOneWidget);
    expect(find.text(_jameson.displayName), findsNothing);
  });

  testWidgets('the shutter rests at five photos', (tester) async {
    await _open(tester, photos: const <String, List<BottleCut>>{});
    for (var i = 0; i < labelCameraShotsMax + 1; i++) {
      await _shoot(tester, '$i.jpg');
    }
    expect(
      find.descendant(
        of: _key('label-camera-shots'),
        matching: find.text('$labelCameraShotsMax'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('검색 adds the drink chosen by name at its place, and says so; '
      'one listed already is not added twice', (tester) async {
    await _open(
      tester,
      photos: <String, List<BottleCut>>{
        'a.jpg': <BottleCut>[_ardbegCut(.05)],
      },
    );
    await _shoot(tester, 'a.jpg');
    await _tap(tester, 'label-camera-results');

    await _tap(tester, 'label-results-search');
    expect(find.text(labelSearchTitle), findsOneWidget);
    expect(_key('taste-fit-label-button'), findsNothing);
    await typeSearch(tester, '글렌피딕');
    await tester.pumpAndSettle();
    await tester.tap(find.text(_glenfiddich.displayName));
    await tester.pumpAndSettle();

    expect(find.byType(LabelResultsScreen), findsOneWidget);
    expect(
      find.text(labelSearchAddedNotice(_glenfiddich.displayName)),
      findsOneWidget,
    );
    expect(_top(tester, _glenfiddich), lessThan(_top(tester, _ardbeg)));
    expect(find.text(labelResultsFoundNote(2)), findsOneWidget);

    await _tap(tester, 'label-results-search');
    await typeSearch(tester, '아드벡');
    await tester.pumpAndSettle();
    await tester.tap(find.text(_ardbeg.displayName).last);
    await tester.pumpAndSettle();
    expect(find.text(labelSearchListedNotice), findsOneWidget);
    expect(find.text(labelResultsFoundNote(2)), findsOneWidget);

    // Leaving the search adds nothing.
    await _tap(tester, 'label-results-search');
    await tester.tap(find.byTooltip('이전 화면으로 이동'));
    await tester.pumpAndSettle();
    expect(find.text(labelResultsFoundNote(2)), findsOneWidget);
  });
}
