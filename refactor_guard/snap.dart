// Temporary: refactor guard. Deleted with refactor_guard/ when the refactor ends.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the pictures go; `GUARD_OUT` or refactor_guard/out.
final Directory guardOut = Directory(
  Platform.environment['GUARD_OUT'] ?? 'refactor_guard/out',
)..createSync(recursive: true);

/// The phone sizes every screen is drawn at.
const guardViewports = <String, Size>{
  'se': Size(375, 667),
  'promax': Size(430, 932),
};

void useViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Lets images and SVGs on screen finish loading, then settles.
Future<void> settleImages(WidgetTester tester) async {
  for (var round = 0; round < 3; round++) {
    final providers = <(ImageProvider, Element)>[];
    final svgs = <(BytesLoader, Element)>[];
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Image) providers.add((widget.image, element));
      if (widget is DecoratedBox) {
        final decoration = widget.decoration;
        if (decoration is BoxDecoration && decoration.image != null) {
          providers.add((decoration.image!.image, element));
        }
      }
      if (widget is SvgPicture) svgs.add((widget.bytesLoader, element));
      element.visitChildren(visit);
    }

    tester.binding.rootElement?.visitChildren(visit);
    await tester.runAsync(() async {
      for (final (provider, element) in providers) {
        await precacheImage(provider, element, onError: (_, _) {});
      }
      for (final (loader, element) in svgs) {
        try {
          await svg.cache.putIfAbsent(
            loader.cacheKey(element),
            () => loader.loadBytes(element),
          );
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }
}

/// Writes what is on screen now as `<name>.png`.
Future<void> snap(WidgetTester tester, String name) async {
  await settleImages(tester);
  final root = tester.binding.rootElement!;
  final bytes = await tester.runAsync(() async {
    final image = await captureImage(root);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  File('${guardOut.path}/$name.png').writeAsBytesSync(bytes!);
}

/// Writes the screen top to bottom: one picture per screenful of the
/// tallest vertical scroll view.
Future<void> snapScrolled(WidgetTester tester, String name) async {
  await snap(tester, '$name.0');
  final scrollables = find.byType(Scrollable).evaluate().where((element) {
    final state = (element as StatefulElement).state as ScrollableState;
    return state.position.axis == Axis.vertical &&
        state.position.maxScrollExtent > 0;
  }).toList();
  if (scrollables.isEmpty) return;
  scrollables.sort((a, b) {
    final pa = ((a as StatefulElement).state as ScrollableState).position;
    final pb = ((b as StatefulElement).state as ScrollableState).position;
    return pb.viewportDimension.compareTo(pa.viewportDimension);
  });
  final position =
      ((scrollables.first as StatefulElement).state as ScrollableState)
          .position;
  final step = position.viewportDimension * 0.8;
  var page = 1;
  for (
    var offset = step;
    offset - step < position.maxScrollExtent && page < 12;
    offset += step, page++
  ) {
    position.jumpTo(offset.clamp(0, position.maxScrollExtent));
    await tester.pumpAndSettle();
    await snap(tester, '$name.$page');
  }
}
