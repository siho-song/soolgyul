import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/label_camera_screen.dart';

import '../support/app_test_harness.dart';

Future<List<String>> _pump(
  WidgetTester tester, {
  LabelCameraStatus status = LabelCameraStatus.ready,
  String hint = labelCameraHint,
  bool flashOn = false,
  bool textDetected = false,
  bool shutterEnabled = true,
}) async {
  final taps = <String>[];
  await pumpTestScreen(
    tester,
    LabelCameraOverlay(
      status: status,
      hint: hint,
      flashOn: flashOn,
      textDetected: textDetected,
      shutterEnabled: shutterEnabled,
      onClose: () => taps.add('close'),
      onToggleFlash: () => taps.add('flash'),
      onOpenSettings: () async => taps.add('settings'),
      onAlbum: () => taps.add('album'),
      onShoot: () => taps.add('shoot'),
      onSearch: () => taps.add('search'),
    ),
  );
  return taps;
}

void main() {
  testWidgets('the viewfinder shows the hints around an empty frame and the '
      'three ways out', (tester) async {
    final taps = await _pump(tester);

    expect(find.text(labelCameraFrameHint), findsOneWidget);
    expect(find.text(labelCameraHint), findsOneWidget);
    expect(find.text(labelCameraTip), findsOneWidget);
    expect(find.byIcon(Icons.flash_off_rounded), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('label-camera-settings')),
      findsNothing,
    );

    for (final key in <String>['album', 'shoot', 'search', 'flash', 'close']) {
      await tester.tap(find.byKey(ValueKey<String>('label-camera-$key')));
    }
    expect(taps, <String>['album', 'shoot', 'search', 'flash', 'close']);
  });

  testWidgets('a dark scene asks for the flash and a waiting shutter ignores '
      'taps', (tester) async {
    final taps = await _pump(
      tester,
      hint: labelCameraDarkHint,
      flashOn: true,
      shutterEnabled: false,
    );

    expect(find.text(labelCameraDarkHint), findsOneWidget);
    expect(find.byIcon(Icons.flash_on_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('label-camera-shoot')));
    expect(taps, isEmpty);
  });

  testWidgets('a denied camera replaces the frame with the settings way', (
    tester,
  ) async {
    final taps = await _pump(tester, status: LabelCameraStatus.denied);

    expect(find.text(labelCameraDenied), findsOneWidget);
    expect(find.text(labelCameraFrameHint), findsNothing);
    expect(find.text(labelCameraHint), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('label-camera-settings')),
    );
    expect(taps, <String>['settings']);
  });

  testWidgets('a device without a camera explains and offers no settings', (
    tester,
  ) async {
    await _pump(tester, status: LabelCameraStatus.noCamera);

    expect(find.text(labelCameraNoCamera), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('label-camera-settings')),
      findsNothing,
    );
  });
}
