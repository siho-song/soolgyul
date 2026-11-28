import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_surface.dart';
import '../../../catalog/data/catalog_drink.dart';
import 'drink_result_photo.dart';
import '../../../../widgets/app_state_view.dart';

/// The rows of a search or a suggestion list. The photos of the first rows
/// are asked for together as soon as the rows are known, without waiting
/// for each row to be laid out.
class DrinkSearchResults extends StatefulWidget {
  const DrinkSearchResults({
    required this.drinks,
    required this.selectedDrink,
    required this.onDrinkSelected,
    this.scrollable = false,
    this.outlined = false,
    this.trailingBuilder,
    this.onEndReached,
    this.loadingMore = false,
    super.key,
  });

  final List<DrinkSelection> drinks;
  final DrinkSelection? selectedDrink;
  final ValueChanged<DrinkSelection> onDrinkSelected;
  final bool scrollable;

  /// A box of its outline alone, the page showing through, in place of the
  /// white raised one: for a list that is part of the page it stands on.
  final bool outlined;

  /// What a row shows at its right instead of the chevron.
  final Widget Function(CatalogDrink drink)? trailingBuilder;

  /// Called when a scrollable list nears its end, to fetch the next page.
  final VoidCallback? onEndReached;

  /// Shows a spinner row under the last result while the next page loads.
  final bool loadingMore;

  /// About as many rows as a phone shows at once.
  static const firstScreenRows = 8;

  @override
  State<DrinkSearchResults> createState() => _DrinkSearchResultsState();
}

class _DrinkSearchResultsState extends State<DrinkSearchResults> {
  /// The photos last asked for; the list is rebuilt on every key typed and
  /// asks again only when its first rows change.
  List<String> _warmedPhotos = const <String>[];

  /// Goes up each time the rows are replaced rather than added to. The
  /// list is keyed by it, so a new answer starts at its top while a next
  /// page leaves the reader where they were.
  int _answer = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmFirstPhotos();
  }

  @override
  void didUpdateWidget(covariant DrinkSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_continues(oldWidget.drinks)) _answer += 1;
    _warmFirstPhotos();
  }

  /// Whether the rows now shown are [before]'s, with or without more after.
  bool _continues(List<DrinkSelection> before) {
    final drinks = widget.drinks;
    if (drinks.length < before.length) return false;
    for (var index = 0; index < before.length; index++) {
      if (drinks[index].catalogId != before[index].catalogId) return false;
    }
    return true;
  }

  void _warmFirstPhotos() {
    final photos = <String>[
      for (final drink in widget.drinks.take(
        DrinkSearchResults.firstScreenRows,
      ))
        ?drink.catalogDrink.photoUrl,
    ];
    if (listEquals(photos, _warmedPhotos)) return;
    _warmedPhotos = photos;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    for (final url in photos) {
      // A photo that fails here shows its placeholder in the row.
      precacheImage(
        DrinkResultPhoto.imageFor(url, pixelRatio: pixelRatio),
        context,
        onError: (_, _) {},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final DrinkSearchResults(:drinks, :scrollable, :loadingMore, :outlined) =
        widget;
    final box = AppSurface(
      borderRadius: AppRadii.compactCard,
      variant: outlined
          ? AppSurfaceVariant.outlined
          : AppSurfaceVariant.elevated,
      backgroundColor: outlined ? Colors.transparent : null,
      boxShadow: outlined ? null : AppShadows.searchResults,
      child: scrollable
          ? NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (isNearScrollEnd(notification)) widget.onEndReached?.call();
                return false;
              },
              child: ListView.separated(
                key: ValueKey<int>(_answer),
                padding: EdgeInsets.zero,
                primary: false,
                // An outline ends under its last row; the white box fills
                // the room it is given.
                shrinkWrap: outlined,
                physics: const ClampingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
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
    return outlined && scrollable
        ? Align(alignment: Alignment.topCenter, child: box)
        : box;
  }

  static const Widget _loadingRow = AppLoadingView(compact: true);

  static const Widget _divider = Divider(
    height: 1,
    indent: 16,
    endIndent: 16,
    color: AppColors.borderSubtle,
  );

  Widget _buildResult(DrinkSelection drink) {
    return _DrinkResultRow(
      drink: drink.catalogDrink,
      selected: widget.selectedDrink?.catalogId == drink.catalogId,
      onTap: () => widget.onDrinkSelected(drink),
      trailing:
          widget.trailingBuilder?.call(drink.catalogDrink) ??
          const AppIcon(
            AppIconAsset.next,
            size: AppSizes.iconMd,
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
            horizontal: AppSpacing.lg,
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
