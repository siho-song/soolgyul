import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/label_camera_screen.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';

import '../support/app_test_harness.dart';

Future<List<String>> _pump(
  WidgetTester tester, {
  LabelCameraStatus status = LabelCameraStatus.ready,
  String? hint,
  bool flashOn = false,
  bool shutterEnabled = true,
  int shots = 0,
  bool backToResults = false,
  Size viewport = defaultAppTestViewport,
}) async {
  final taps = <String>[];
  await pumpTestScreen(
    tester,
    LabelCameraOverlay(
      status: status,
      hint: hint,
      flashOn: flashOn,
      textDetected: false,
      shutterEnabled: shutterEnabled,
      shots: <XFile>[for (var i = 0; i < shots; i++) XFile('/photos/$i.jpg')],
      backToResults: backToResults,
      onClose: () => taps.add('close'),
      onToggleFlash: () => taps.add('flash'),
      onOpenSettings: () async => taps.add('settings'),
      onShoot: () => taps.add('shoot'),
      onReviewShots: () => taps.add('shots'),
      onResults: () => taps.add('results'),
    ),
    viewport: viewport,
  );
  return taps;
}

Finder _key(String name) => find.byKey(ValueKey<String>('label-camera-$name'));

void main() {
  testWidgets('before the first photo the shutter stands alone under what to '
      'shoot', (tester) async {
    final taps = await _pump(tester);

    expect(find.text(labelCameraGuide), findsOneWidget);
    expect(find.byIcon(Icons.flash_off_rounded), findsOneWidget);
    expect(_key('shots'), findsNothing);
    expect(_key('results'), findsNothing);
    expect(_key('album'), findsNothing);
    expect(_key('search'), findsNothing);

    for (final key in <String>['shoot', 'flash', 'close']) {
      await tester.tap(_key(key));
    }
    expect(taps, <String>['shoot', 'flash', 'close']);
  });

  testWidgets('photos taken stand in a stack with their number, beside the '
      'way on, and the line above the shutter is empty', (tester) async {
    final taps = await _pump(tester, shots: 3);

    expect(find.text(labelCameraGuide), findsNothing);
    expect(
      find.descendant(of: _key('shots'), matching: find.text('3')),
      findsOneWidget,
    );
    await tester.tap(_key('shots'));
    await tester.tap(_key('results'));
    expect(taps, <String>['shots', 'results']);
  });

  testWidgets('what is wrong with the scene replaces the line, before and '
      'after the first photo', (tester) async {
    await _pump(tester, hint: labelCameraDarkHint);
    expect(find.text(labelCameraDarkHint), findsOneWidget);
    expect(find.text(labelCameraGuide), findsNothing);

    await _pump(tester, hint: labelCameraCrowdedHint, shots: 1);
    expect(find.text(labelCameraCrowdedHint), findsOneWidget);
  });

  testWidgets('a waiting shutter ignores taps', (tester) async {
    final taps = await _pump(
      tester,
      hint: labelCameraFullHint,
      shutterEnabled: false,
      shots: labelCameraShotsMax,
    );

    expect(find.text(labelCameraFullHint), findsOneWidget);
    await tester.tap(_key('shoot'));
    expect(taps, isEmpty);
  });

  testWidgets('opened from the finds, the top left is the way back to them', (
    tester,
  ) async {
    await _pump(tester);
    AppIcon icon() => tester.widget<AppIcon>(
      find.descendant(of: _key('close'), matching: find.byType(AppIcon)),
    );
    expect(icon().icon, AppIconAsset.close);

    await _pump(tester, backToResults: true);
    expect(icon().icon, AppIconAsset.previous);
  });

  testWidgets('in a short window nothing overflows', (tester) async {
    // A phone in split screen: about half its height.
    await _pump(tester, viewport: const Size(411, 435), shots: 2);

    expect(tester.takeException(), isNull);
    expect(_key('shoot'), findsOneWidget);
  });

  testWidgets('a denied camera says so and shows the way to the settings', (
    tester,
  ) async {
    final taps = await _pump(tester, status: LabelCameraStatus.denied);

    expect(find.text(labelCameraDenied), findsOneWidget);
    expect(find.text(labelCameraGuide), findsNothing);
    await tester.tap(_key('settings'));
    expect(taps, <String>['settings']);
  });

  testWidgets('a device without a camera explains and offers no settings', (
    tester,
  ) async {
    await _pump(tester, status: LabelCameraStatus.noCamera);

    expect(find.text(labelCameraNoCamera), findsOneWidget);
    expect(_key('settings'), findsNothing);
  });
}
