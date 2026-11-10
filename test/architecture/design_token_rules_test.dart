import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Feature screens take colours, font sizes, corner radii, gaps and
/// durations from `design/app_tokens.dart` and `design/app_typography.dart`.
/// The files below still write some by hand (the 술결 card and the camera
/// keep their own look); their counts may only go down, and no other
/// feature file may start.
void main() {
  const allowed = <String, int>{
    'home/presentation/soolgyul_letters_detail_sections.dart': 4,
    'onboarding/presentation/auth/app_loading_screen.dart': 2,
    'onboarding/presentation/auth/login_screen.dart': 2,
    'onboarding/presentation/auth/profile_setup_screen.dart': 6,
    'onboarding/presentation/auth/social_login_actions.dart': 8,
    'onboarding/presentation/sensory/aroma_picker.dart': 1,
    'onboarding/presentation/widgets/onboarding_actions.dart': 2,
    'onboarding/presentation/widgets/onboarding_choice_controls.dart': 1,
    'preferences/presentation/history/preference_history_calendar.dart': 6,
    'preferences/presentation/history/preference_history_daily_records.dart': 1,
    'preferences/presentation/history/preference_history_monthly_summary.dart':
        1,
    'profile/presentation/widgets/drink_select_card.dart': 1,
    'profile/presentation/widgets/profile_hero.dart': 1,
    'profile/presentation/widgets/profile_liked_record_widgets.dart': 1,
    'profile/presentation/widgets/profile_record_cards.dart': 1,
    'taste_card/data/taste_card_wire_reading.dart': 1,
    'taste_card/presentation/card/taste_card_bite_section.dart': 7,
    'taste_card/presentation/card/taste_card_common.dart': 11,
    'taste_card/presentation/card/taste_card_drink_header.dart': 3,
    'taste_card/presentation/card/taste_card_reason_section.dart': 2,
    'taste_card/presentation/taste_card_screen.dart': 6,
    'taste_card/presentation/widgets/taste_card_guide_body.dart': 19,
    'taste_card/presentation/widgets/taste_card_guide_parts.dart': 7,
    'taste_fit/data/catalog_search_session.dart': 1,
    'taste_fit/presentation/label_camera_screen.dart': 1,
    'taste_fit/presentation/taste_fit_detail_screen.dart': 1,
    'taste_fit/presentation/widgets/label_camera_overlay.dart': 6,
    'taste_fit/presentation/widgets/taste_fit_headline.dart': 1,
    'taste_fit/presentation/widgets/taste_fit_paper_card.dart': 1,
  };

  final handWritten = <RegExp>[
    RegExp(r'Color\(0x'),
    RegExp(r'fontSize:\s*[\d.]'),
    RegExp(r'Radius\.circular\(\s*[\d.]'),
    RegExp(r'SizedBox\((?:height|width):\s*[\d.]+\)'),
    RegExp(r'Duration\(milliseconds:'),
  ];

  test('feature screens add no hand-written design values', () {
    final root = Directory('lib/src/features').absolute.path;
    final over = <String>[];
    for (final file in Directory(root).listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      final count = handWritten.fold<int>(
        0,
        (sum, pattern) => sum + pattern.allMatches(source).length,
      );
      final name = file.path.substring(root.length + 1);
      final limit = allowed[name] ?? 0;
      if (count > limit) over.add('$name: $count hand-written, $limit allowed');
    }
    expect(over, isEmpty, reason: 'use a token from lib/src/design instead');
  });
}
