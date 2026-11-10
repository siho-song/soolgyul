import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_surface.dart';
import '../../../catalog/data/catalog_drink.dart';
import 'drink_result_photo.dart';

class DrinkSearchResults extends StatelessWidget {
  const DrinkSearchResults({
    required this.drinks,
    required this.selectedDrink,
    required this.onDrinkSelected,
    this.scrollable = false,
    this.trailingBuilder,
    this.onEndReached,
    this.loadingMore = false,
    super.key,
  });

  final List<DrinkSelection> drinks;
  final DrinkSelection? selectedDrink;
  final ValueChanged<DrinkSelection> onDrinkSelected;
  final bool scrollable;

  /// What a row shows at its right instead of the chevron.
  final Widget Function(CatalogDrink drink)? trailingBuilder;

  /// Called when a scrollable list nears its end, to fetch the next page.
  final VoidCallback? onEndReached;

  /// Shows a spinner row under the last result while the next page loads.
  final bool loadingMore;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      borderRadius: AppRadii.compactCard,
      variant: AppSurfaceVariant.elevated,
      boxShadow: AppShadows.searchResults,
      child: scrollable
          ? NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (isNearScrollEnd(notification)) onEndReached?.call();
                return false;
              },
              child: ListView.separated(
                padding: EdgeInsets.zero,
                primary: false,
                physics: const ClampingScrollPhysics(),
                itemCount: drinks.length + (loadingMore ? 1 : 0),
                separatorBuilder: (_, _) => _divider,
                itemBuilder: (context, index) => index == drinks.length
                    ? _loadingRow
                    : _buildResult(drinks[index]),
              ),
            )
          : Column(
              children: <Widget>[
                for (var index = 0; index < drinks.length; index++) ...[
                  _buildResult(drinks[index]),
                  if (index != drinks.length - 1) _divider,
                ],
                if (loadingMore) ...[_divider, _loadingRow],
              ],
            ),
    );
  }

  static const Widget _loadingRow = Padding(
    padding: EdgeInsets.all(AppSpacing.md),
    child: Center(
      child: SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );

  static const Widget _divider = Divider(
    height: 1,
    indent: 16,
    endIndent: 16,
    color: AppColors.borderSubtle,
  );

  Widget _buildResult(DrinkSelection drink) {
    return _DrinkResultRow(
      drink: drink.catalogDrink,
      selected: selectedDrink?.catalogId == drink.catalogId,
      onTap: () => onDrinkSelected(drink),
      trailing:
          trailingBuilder?.call(drink.catalogDrink) ??
          const AppIcon(
            AppIconAsset.next,
            size: 18,
            color: AppColors.textSecondary,
          ),
    );
  }
}

/// Whether a scroll has come within a few rows of the end of its list.
bool isNearScrollEnd(ScrollNotification notification) =>
    notification.metrics.axis == Axis.vertical &&
    notification.metrics.extentAfter < 240;

/// One result: photo, then name, English name and style · ABV.
class _DrinkResultRow extends StatelessWidget {
  const _DrinkResultRow({
    required this.drink,
    required this.selected,
    required this.onTap,
    required this.trailing,
  });

  final CatalogDrink drink;
  final bool selected;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final facts = <String>[?drink.styleLabel, ?drink.abvLabel].join(' · ');
    return Material(
      color: selected ? AppColors.surfaceSoft : Colors.transparent,
      // Taking focus here would hand it back to the search field once the
      // list closes, reselecting the chosen name.
      child: InkWell(
        canRequestFocus: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              DrinkResultPhoto(url: drink.photoUrl, selected: selected),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      drink.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.menuItemTitle,
                    ),
                    if (drink.nameEn case final nameEn?)
                      Text(
                        nameEn,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption,
                      ),
                    if (facts.isNotEmpty)
                      Text(
                        facts,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption,
                      ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
