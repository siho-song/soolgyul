import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_surface.dart';
import '../../../catalog/data/catalog_drink.dart';
import '../../../catalog/data/catalog_place_names.dart';
import 'drink_result_photo.dart';

/// Over the candidates a label photo found besides the one on the card.
const String otherCandidatesTitle = '비슷한 다른 술';

/// The chosen product, shown once the result list closes so the visitor can
/// check it is the bottle they drank before answering about it; also the
/// likeliest bottle a label photo found.
class SelectedDrinkCard extends StatelessWidget {
  const SelectedDrinkCard({
    required this.drink,
    this.verdict,
    this.onTap,
    super.key,
  });

  final CatalogDrink drink;

  /// A line under the name, such as the taste-fit verdict.
  final Widget? verdict;

  /// Makes the whole card a button.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final facts = <String>[
      ?drink.styleLabel,
      ?CatalogPlaceNames.place(
        countryCode: drink.countryCode,
        regionPath: drink.region,
      ),
      ?drink.abvLabel,
    ].join(' · ');
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const Text('찾으시는 술이 맞나요?', style: AppTextStyles.cardTitle),
          const SizedBox(height: AppSpacing.xl),
          DrinkResultPhoto(url: drink.photoUrl, selected: false, size: 148),
          const SizedBox(height: AppSpacing.lg),
          Text(
            drink.displayName,
            textAlign: TextAlign.center,
            style: AppTextStyles.cardTitle,
          ),
          if (verdict case final verdict?) ...<Widget>[
            const SizedBox(height: AppSpacing.s6),
            verdict,
          ],
          if (drink.nameEn case final nameEn?) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              nameEn,
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
          ],
          if (facts.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              facts,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption,
            ),
          ],
        ],
      ),
    );
    return AppSurface(
      borderRadius: AppRadii.compactCard,
      variant: AppSurfaceVariant.elevated,
      backgroundColor: Colors.white.withValues(alpha: .88),
      boxShadow: AppShadows.searchResults,
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap, child: content),
            ),
    );
  }
}
