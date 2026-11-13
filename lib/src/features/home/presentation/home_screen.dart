import 'package:flutter/material.dart';
import '../../../design/app_feature_layouts.dart';
import '../../../widgets/kept_text.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../../../widgets/app_surface.dart';
import '../data/next_drink_guides.dart';
import '../data/taste_letters.dart';
import 'next_drink_guide_card.dart';
import 'soolgyul_letters_card.dart';
import 'taste_fit_search_entry.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onOpenSoolgyulLetters,
    required this.onOpenCard,
    required this.onOpenTasteFit,
    this.onScanLabel,
    this.onRefresh,
    this.tasteFitKey,
    this.lettersKey,
    this.guidesKey,
    this.guidesLevelsKey,
    this.exampleLetters,
    this.exampleGuides,
    super.key,
  });

  final VoidCallback onOpenSoolgyulLetters;

  /// Opens a saved card by its result ID.
  final ValueChanged<String> onOpenCard;
  final VoidCallback onOpenTasteFit;

  /// Opens the taste-fit search straight into a label photo; `null` hides
  /// the camera button (the web reads no labels).
  final VoidCallback? onScanLabel;

  /// Pulling home down asks for the letters and guides again, for a card
  /// saved on the web or another device.
  final Future<void> Function()? onRefresh;

  /// Hung on the three parts so the tour can point at them.
  final Key? tasteFitKey;
  final Key? lettersKey;
  final Key? guidesKey;

  /// Hung on the example guide's box of marks.
  final Key? guidesLevelsKey;

  /// Made-up letters and guides shown in place of the member's own while
  /// the tour explains a home that has none yet.
  final TasteLettersState? exampleLetters;
  final List<NextDrinkGuide>? exampleGuides;

  @override
  Widget build(BuildContext context) {
    return MainTabScrollView(
      topPadding: AppSpacing.sm,
      onRefresh: onRefresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppPanel(
            key: tasteFitKey,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text('고민 중인 술이 있나요?', style: AppTextStyles.sectionTitle),
                const SizedBox(height: AppSpacing.sm),
                const KeptText(
                  '라벨을 촬영하거나 검색해\n내 입맛과의 궁합을 확인해 보세요.',
                  style: AppTextStyles.detail,
                ),
                const SizedBox(height: AppSpacing.s14),
                TasteFitSearchEntry(
                  onOpen: onOpenTasteFit,
                  onScanLabel: onScanLabel,
                ),
              ],
            ),
          ),
          const SizedBox(height: HomeLayoutSpacing.cardGap),
          SoolgyulLettersCard(
            key: lettersKey,
            onOpen: onOpenSoolgyulLetters,
            example: exampleLetters,
          ),
          const SizedBox(height: HomeLayoutSpacing.cardGap),
          NextDrinkGuideCard(
            key: guidesKey,
            onOpenCard: onOpenCard,
            example: exampleGuides,
            exampleLevelsKey: guidesLevelsKey,
          ),
        ],
      ),
    );
  }
}
