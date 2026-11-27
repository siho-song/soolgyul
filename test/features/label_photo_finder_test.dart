import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/catalog_search_session.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_layout.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_photo_finder.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_text_recognizer.dart';

import '../support/fake_search.dart';

const _doubleWood = CatalogDrink(
  id: 'balvenie-12',
  displayName: '발베니 12년 더블우드',
  nameEn: 'The Balvenie 12 DoubleWood',
  category: DrinkCategory.whisky,
);

const _doubleWood17 = CatalogDrink(
  id: 'balvenie-17',
  displayName: '발베니 17년 더블우드',
  nameEn: 'The Balvenie 17 DoubleWood',
  category: DrinkCategory.whisky,
);

/// The front of a Balvenie bottle as a phone reads it, its age unread: the
/// label match cannot tell the two DoubleWoods apart.
const _balvenieLabel = <String>['THE BALVENIE', 'DoubleWood'];

BottleBox _placed(double left, double top, double bottom) =>
    BottleBox(left: left, top: top, right: left + 0.2, bottom: bottom);

/// Finds both DoubleWoods for every label and judges the bottle's photo as
/// [answer] says: a drink's id, `null` for none of them, or no answer at
/// all when it throws.
class _JudgingCatalog extends FakeCatalog implements LabelPhotoJudge {
  _JudgingCatalog(this.answer)
    : super(const <CatalogDrink>[_doubleWood, _doubleWood17]);

  final String? Function() answer;
  final List<({List<String> ids, bool appSure, int photoBytes})> asked =
      <({List<String> ids, bool appSure, int photoBytes})>[];

  @override
  Future<String?> pickByPhoto(
    Uint8List photo,
    List<String> candidateIds, {
    required bool appSure,
  }) async {
    asked.add((ids: candidateIds, appSure: appSure, photoBytes: photo.length));
    return answer();
  }
}

Future<LabelPhotoFound> _find(
  CatalogSearchGateway catalog,
  LabelTextRecognizer recognizer,
) => LabelPhotoFinder(
  catalog,
).readAndFind(recognizer, labelPhotoPath, current: () => true, onRead: (_) {});

void main() {
  test('of several bottles the one nearest the middle is tried first', () {
    final edge = _placed(0.0, 0.1, 0.9);
    final middle = _placed(0.4, 0.1, 0.9);
    expect(nearestMiddle(<BottleBox>[edge, middle]), <BottleBox>[middle, edge]);
  });

  test('of a photo of several only the bottle nearest the middle that shows '
      'text is read', () async {
    final far = bottleCut(0.0, const <String>['아드벡', '10년']);
    final blank = (
      box: const BottleBox(left: 0.35, top: 0.1, right: 0.65, bottom: 0.9),
      lines: const <ReadLine>[],
    );
    final next = bottleCut(0.55, _balvenieLabel);
    final recognizer = FakeBottleReader(<BottleCut>[far, blank, next]);
    final session = CatalogSearchSession(
      () => FakeCatalog(const <CatalogDrink>[_doubleWood]),
    );
    addTearDown(session.dispose);

    await session.scanLabel(recognizer, XFile(labelPhotoPath));

    expect(recognizer.read, <BottleBox>[blank.box, next.box]);
    expect(recognizer.wholeReads, 0);
    expect(session.matches.first.id, _doubleWood.id);
  });

  group('a photo of one bottle is put to the judge', () {
    test('the drink it names is the one find, and sure', () async {
      final catalog = _JudgingCatalog(() => _doubleWood17.id);
      final recognizer = FakeBottleReader(const <BottleCut>[]);

      final found = await _find(catalog, recognizer);

      expect(found.finds.single.search.matches, <CatalogDrink>[_doubleWood17]);
      expect(found.finds.single.search.sure, isTrue);
      expect(found.finds.single.search.tied, isFalse);
      expect(found.queries, isNotEmpty);
      // Shown the bottle the phone itself picks out of a photo read whole,
      // and the label match's candidates.
      expect(recognizer.photographed, <BottleBox?>[null]);
      expect(
        catalog.asked.single.ids,
        unorderedEquals(<String>[_doubleWood.id, _doubleWood17.id]),
      );
      expect(catalog.asked.single.photoBytes, 2);
    });

    test(
      'a judge sure of none leaves no find, only what was searched',
      () async {
        final catalog = _JudgingCatalog(() => null);

        final found = await _find(
          catalog,
          FakeBottleReader(const <BottleCut>[]),
        );

        expect(found.finds, isEmpty);
        expect(found.queries, isNotEmpty);
      },
    );

    test('a judge that gives no answer leaves the label match\'s '
        'candidates', () async {
      final catalog = _JudgingCatalog(
        () => throw const LabelPhotoJudgeException(),
      );

      final found = await _find(catalog, FakeBottleReader(const <BottleCut>[]));

      expect(found.finds.single.search.matches, hasLength(2));
    });

    test('a phone that cannot make the bottle\'s photo asks nothing', () async {
      final catalog = _JudgingCatalog(() => _doubleWood17.id);

      final found = await _find(
        catalog,
        FakeBottleReader(const <BottleCut>[], jpeg: null),
      );

      expect(catalog.asked, isEmpty);
      expect(found.finds.single.search.matches, hasLength(2));
    });

    test('a catalog without a judge has no photo made', () async {
      final recognizer = FakeBottleReader(const <BottleCut>[]);

      await _find(
        FakeCatalog(const <CatalogDrink>[_doubleWood, _doubleWood17]),
        recognizer,
      );

      expect(recognizer.photographed, isEmpty);
    });

    test('the bottle read out of several is the one photographed', () async {
      final catalog = _JudgingCatalog(() => _doubleWood.id);
      final middle = bottleCut(0.35, _balvenieLabel);
      final recognizer = FakeBottleReader(<BottleCut>[
        bottleCut(0.0, const <String>['아드벡', '10년']),
        middle,
      ]);

      final found = await _find(catalog, recognizer);

      expect(recognizer.photographed, <BottleBox?>[middle.box]);
      expect(found.finds.single.search.matches, <CatalogDrink>[_doubleWood]);
    });

    test('a search repeated after a failure judges the same photo '
        'again', () async {
      final catalog = _JudgingCatalog(() => _doubleWood.id);
      final recognizer = FakeBottleReader(const <BottleCut>[]);
      final finder = LabelPhotoFinder(catalog);
      late LabelPhotoRead kept;
      await finder.readAndFind(
        recognizer,
        labelPhotoPath,
        current: () => true,
        onRead: (read) => kept = read,
      );

      final again = await finder.find(kept);

      expect(again.finds.single.search.matches, <CatalogDrink>[_doubleWood]);
      expect(catalog.asked, hasLength(2));
      expect(recognizer.photographed, hasLength(1));
    });
  });

  test('a session shows the judged drink alone, and a miss as a label '
      'nobody matches', () async {
    String? answer = _doubleWood17.id;
    final catalog = _JudgingCatalog(() => answer);
    final events = FakeDiscoveryEvents();
    final session = CatalogSearchSession(() => catalog, events: () => events);
    addTearDown(session.dispose);
    final recognizer = FakeBottleReader(const <BottleCut>[]);

    await session.scanLabel(recognizer, XFile(labelPhotoPath));
    expect(session.matches, <CatalogDrink>[_doubleWood17]);

    answer = null;
    await session.scanLabel(recognizer, XFile(labelPhotoPath));
    expect(session.matches, isEmpty);
    expect(session.labelQueries, isNotEmpty);
    expect(events.events.last, startsWith('label_miss '));
  });
}
