import 'package:flutter/material.dart';
import '../../../design/app_feature_layouts.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../../../widgets/app_surface.dart';
import 'next_drink_guide_card.dart';
import 'soolgyul_letters_card.dart';
import 'taste_fit_search_entry.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onOpenSoolgyulLetters,
    required this.onOpenCard,
    required this.onOpenTasteFit,
    this.onScanLabel,
    super.key,
  });

  final VoidCallback onOpenSoolgyulLetters;

  /// Opens a saved card by its result ID.
  final ValueChanged<String> onOpenCard;
  final VoidCallback onOpenTasteFit;

  /// Opens the taste-fit search straight into a label photo; `null` hides
  /// the camera button (the web reads no labels).
  final VoidCallback? onScanLabel;

  @override
  Widget build(BuildContext context) {
    return MainTabScrollView(
      topPadding: AppSpacing.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppPanel(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              18,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text('고민 중인 술이 있나요?', style: AppTextStyles.sectionTitle),
                const SizedBox(height: 6),
                const Text(
                  '병 라벨을 비추거나 검색해\n내 입맛과의 궁합을 확인해보세요.',
                  style: AppTextStyles.homeWelcomeMessage,
                ),
                const SizedBox(height: 14),
                TasteFitSearchEntry(
                  onOpen: onOpenTasteFit,
                  onScanLabel: onScanLabel,
                ),
              ],
            ),
          ),
          const SizedBox(height: HomeLayoutSpacing.cardGap),
          SoolgyulLettersCard(onOpen: onOpenSoolgyulLetters),
          const SizedBox(height: HomeLayoutSpacing.cardGap),
          NextDrinkGuideCard(onOpenCard: onOpenCard),
        ],
      ),
    );
  }
}
