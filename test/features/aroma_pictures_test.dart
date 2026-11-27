import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';

/// A chip's picture is a file named by its key, so a chip added to a menu
/// without its picture would be drawn as a broken image, and a picture no
/// chip draws would only weigh on the bundle.
void main() {
  const folder = 'assets/icons/aromas';

  test('every aroma chip has its picture in the bundle, and the bundle holds '
      'no picture no chip draws', () {
    final files = {
      for (final file in Directory(folder).listSync().whereType<File>())
        file.path.replaceAll('\\', '/'),
    };
    expect(files, {
      for (final chip in OnboardingAromaMenu.chips) '$folder/${chip.key}.webp',
    });
    for (final chip in OnboardingAromaMenu.chips) {
      expect(chip.picture, '$folder/${chip.key}.webp');
    }
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('    - $folder/\n'),
    );
  });
}
