import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/recording/presentation/widgets/drink_result_photo.dart';
import 'package:soolgyul/src/features/recording/presentation/widgets/drink_search_results.dart';
import 'package:soolgyul/src/widgets/app_network_image.dart';
import 'package:soolgyul/src/widgets/drink_photo_placeholder.dart';

/// Stands in for a download: keeps the address asked for and hands over the
/// picture when the test lets it arrive.
class _PendingPhoto extends ImageProvider<_PendingPhoto> {
  const _PendingPhoto(this.url, this.asked, this.arrival);

  final String url;
  final List<String> asked;
  final Future<ImageInfo> arrival;

  @override
  Future<_PendingPhoto> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_PendingPhoto>(this);

  @override
  ImageStreamCompleter loadImage(
    _PendingPhoto key,
    ImageDecoderCallback decode,
  ) {
    asked.add(url);
    return OneFrameImageStreamCompleter(arrival);
  }

  @override
  bool operator ==(Object other) => other is _PendingPhoto && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

List<DrinkSelection> _bottles(int count) => <DrinkSelection>[
  for (var n = 1; n <= count; n++)
    DrinkSelection.catalogMatch(
      CatalogDrink(
        id: 'drink-$n',
        displayName: '발베니 $n',
        category: DrinkCategory.whisky,
        photoUrl: 'https://photos.test/$n.webp',
      ),
    ),
];

/// Shows [drinks] with their photos held back: [asked] keeps the addresses
/// asked for, and the photos arrive when the test completes [arrival].
Future<void> _pumpResults(
  WidgetTester tester,
  List<DrinkSelection> drinks, {
  required List<String> asked,
  Future<ImageInfo>? arrival,
  bool scrollable = false,
}) {
  // A photo nobody lets arrive stays on its way for the whole test.
  final photo = arrival ?? Completer<ImageInfo>().future;
  networkImageProvider = (url) => _PendingPhoto(url, asked, photo);
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          // Shorter than the eight rows warmed, so some are not laid out.
          child: SizedBox(
            height: scrollable ? 100 : null,
            child: DrinkSearchResults(
              drinks: drinks,
              selectedDrink: null,
              onDrinkSelected: (_) {},
              scrollable: scrollable,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final download = networkImageProvider;

  tearDown(() {
    networkImageProvider = download;
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  testWidgets('a photo on its way shows the placeholder, then fades in', (
    tester,
  ) async {
    final picture = await tester.runAsync(
      () => createTestImage(width: 4, height: 5),
    );
    final arrival = Completer<ImageInfo>();
    await _pumpResults(
      tester,
      _bottles(1),
      asked: <String>[],
      arrival: arrival.future,
    );
    final frame = find.byType(DrinkResultPhoto);
    final photo = find.descendant(
      of: frame,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RawImage && (widget.image?.isCloneOf(picture!) ?? false),
      ),
    );
    double opacityOf(Finder shown) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: shown, matching: find.byType(AnimatedOpacity)),
        )
        .opacity;
    expect(opacityOf(find.byType(DrinkPhotoPlaceholder)), 1);
    expect(photo, findsNothing);

    arrival.complete(ImageInfo(image: picture!));
    await tester.pumpAndSettle();

    expect(opacityOf(find.byType(DrinkPhotoPlaceholder)), 0);
    expect(opacityOf(photo), 1);
  });

  testWidgets('a photo is decoded at the height of its frame', (tester) async {
    await _pumpResults(tester, _bottles(1), asked: <String>[]);

    final photo = tester.widget<Image>(
      find.descendant(
        of: find.byType(DrinkResultPhoto),
        matching: find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is ResizeImage,
        ),
      ),
    );
    final decoded = photo.image as ResizeImage;
    expect(
      decoded.height,
      (DrinkResultPhoto.listSize * tester.view.devicePixelRatio).ceil(),
    );
    expect(decoded.width, isNull);
  });

  testWidgets('the first rows have their photos asked for at once', (
    tester,
  ) async {
    final bottles = _bottles(20);
    final asked = <String>[];
    List<String> photosOf(Iterable<DrinkSelection> rows) => <String>[
      for (final row in rows) row.catalogDrink.photoUrl!,
    ];
    await _pumpResults(tester, bottles, asked: asked, scrollable: true);

    // Fewer rows than that are laid out, and each photo is asked for once.
    expect(find.text('발베니 8'), findsNothing);
    final firstScreen = photosOf(
      bottles.take(DrinkSearchResults.firstScreenRows),
    );
    expect(asked, firstScreen);

    // The same rows again (the list is rebuilt on every key) ask nothing.
    await _pumpResults(
      tester,
      List.of(bottles),
      asked: asked,
      scrollable: true,
    );
    expect(asked, firstScreen);

    // New rows have theirs asked for.
    final next = bottles.skip(10).toList();
    await _pumpResults(tester, next, asked: asked, scrollable: true);
    expect(asked, <String>[...firstScreen, ...photosOf(next.take(8))]);
  });

  testWidgets('dragging the results takes the keyboard off the search field', (
    tester,
  ) async {
    networkImageProvider = (url) =>
        _PendingPhoto(url, <String>[], Completer<ImageInfo>().future);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              TextField(focusNode: focus, autofocus: true),
              SizedBox(
                height: 100,
                child: DrinkSearchResults(
                  drinks: _bottles(8),
                  selectedDrink: null,
                  onDrinkSelected: (_) {},
                  scrollable: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.drag(find.byType(ListView), const Offset(0, -60));
    await tester.pump();

    expect(focus.hasFocus, isFalse);
  });
}
