import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../catalog/data/catalog_drink.dart';
import 'drink_search_results.dart';

const String labelMatchQuestion = '이 술이 맞나요?';
const String labelMatchOthersTitle = '다른 후보';

/// What a label photo found: the likeliest bottle asked about on its own,
/// then the other candidates. A tap on either does what a tap on a search
/// result does on that screen.
class LabelMatchResults extends StatelessWidget {
  const LabelMatchResults({
    required this.drinks,
    required this.selectedDrink,
    required this.onDrinkSelected,
    this.scrollable = false,
    this.trailingBuilder,
    super.key,
  }) : assert(drinks.length > 0);

  /// The candidates, likeliest first.
  final List<DrinkSelection> drinks;
  final DrinkSelection? selectedDrink;
  final ValueChanged<DrinkSelection> onDrinkSelected;

  /// Whether the other candidates scroll in the space left (a screen of
  /// their own) or sit in the page's scroll.
  final bool scrollable;
  final Widget Function(CatalogDrink drink)? trailingBuilder;

  @override
  Widget build(BuildContext context) {
    final others = DrinkSearchResults(
      key: const ValueKey<String>('label-match-others'),
      drinks: drinks.sublist(1),
      selectedDrink: selectedDrink,
      onDrinkSelected: onDrinkSelected,
      scrollable: scrollable,
      trailingBuilder: trailingBuilder,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
      children: <Widget>[
        const Text(labelMatchQuestion, style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSpacing.sm),
        DrinkSearchResults(
          key: const ValueKey<String>('label-match-best'),
          drinks: drinks.sublist(0, 1),
          selectedDrink: selectedDrink,
          onDrinkSelected: onDrinkSelected,
          trailingBuilder: trailingBuilder,
        ),
        if (drinks.length > 1) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          const Text(labelMatchOthersTitle, style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          if (scrollable) Expanded(child: others) else others,
        ],
      ],
    );
  }
}
