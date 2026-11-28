import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_chip.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_paper.dart';
import '../../../widgets/app_surface.dart';
import '../../catalog/data/catalog_drink.dart';
import '../data/taste_fit_verdict.dart';
import 'widgets/taste_fit_badge.dart';

const String labelResultsMoreLabel = '더 찍기';
const String labelResultsSearchLabel = '검색';
const String labelResultsRankTitle = '잘 맞는 술 순위';

/// The title when no find has a face to rank by.
const String labelResultsFoundTitle = '찾은 술';
String labelResultsFoundNote(int found) => '찍은 사진에서 $found병을 찾았어요.';

/// Over the finds without a face, which stand apart from the ranked ones.
const String labelResultsUnjudgedNote = '해당 주종의 기록이 없어서 판정할 수 없어요';
const String labelResultsNoneTitle = '술을 찾지 못했어요';
const String labelResultsNoneNote = '라벨이 잘 보이게 가까이에서 다시 찍거나\n이름으로 검색해 보세요.';

/// [finds] best fit first, each with its face; drinks of one face keep the
/// order they are in. A drink without a face is left out.
List<(CatalogDrink, TasteFitBadge)> labelFindsRanked(
  List<CatalogDrink> finds,
  TasteFitResponse? fit,
) {
  if (fit == null || !fit.hasCards) {
    return const <(CatalogDrink, TasteFitBadge)>[];
  }
  final faced = <(int, CatalogDrink, TasteFitBadge)>[
    for (final (index, drink) in finds.indexed)
      if (fit.verdictFor(drink.id)?.badge case final badge?
          when badge != TasteFitBadge.noInfo)
        (index, drink, badge),
  ];
  faced.sort((a, b) {
    final byFit = a.$3.index.compareTo(b.$3.index);
    return byFit != 0 ? byFit : a.$1.compareTo(b.$1);
  });
  return <(CatalogDrink, TasteFitBadge)>[
    for (final (_, drink, badge) in faced) (drink, badge),
  ];
}

/// The drinks the photos showed, on a screen of their own: the ones with a
/// fit face ranked best first, then the ones the reader has no record of
/// their kind to judge by, under the sentence that says so. 더 찍기 and 검색
/// stand at the top left and the ✕ that closes the finds at the top right.
/// A row opens the drink's fit page; a drink among 저장한 술 wears a small
/// heart after its name.
class LabelResultsScreen extends StatelessWidget {
  const LabelResultsScreen({
    required this.finds,
    required this.fit,
    required this.saved,
    required this.onMore,
    required this.onSearch,
    required this.onClose,
    required this.onSelect,
    super.key,
  });

  /// In the order found.
  final List<CatalogDrink> finds;
  final TasteFitResponse? fit;

  /// The ids of the finds among 저장한 술.
  final Set<String> saved;
  final VoidCallback onMore;
  final VoidCallback onSearch;
  final VoidCallback onClose;
  final ValueChanged<CatalogDrink> onSelect;

  @override
  Widget build(BuildContext context) {
    final ranked = labelFindsRanked(finds, fit);
    final rankedIds = <String>{for (final (drink, _) in ranked) drink.id};
    final unjudged = <CatalogDrink>[
      for (final drink in finds)
        if (!rankedIds.contains(drink.id)) drink,
    ];
    return AppPaperScaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: 48,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: AppSpacing.sheetX),
                  AppChip(
                    key: const ValueKey<String>('label-results-more'),
                    label: labelResultsMoreLabel,
                    leadingIcon: AppIconAsset.camera,
                    variant: AppChipVariant.outline,
                    tone: AppChipTone.neutral,
                    onPressed: onMore,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppChip(
                    key: const ValueKey<String>('label-results-search'),
                    label: labelResultsSearchLabel,
                    leadingIcon: AppIconAsset.search,
                    variant: AppChipVariant.outline,
                    tone: AppChipTone.neutral,
                    onPressed: onSearch,
                  ),
                  const Spacer(),
                  AppIconButton(
                    key: const ValueKey<String>('label-results-close'),
                    tooltip: '닫기',
                    onPressed: onClose,
                    child: const AppIcon(
                      AppIconAsset.close,
                      size: AppSizes.iconLg,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
              ),
            ),
            Expanded(
              child: finds.isEmpty
                  ? const _NothingFound()
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.sheetX,
                        AppSpacing.xxl,
                        AppSpacing.sheetX,
                        AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
                      ),
                      children: <Widget>[
                        Text(
                          ranked.isEmpty
                              ? labelResultsFoundTitle
                              : labelResultsRankTitle,
                          style: AppTextStyles.sheetTitle,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          labelResultsFoundNote(finds.length),
                          style: AppTextStyles.sheetBody,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (ranked.isNotEmpty)
                          _Rows(
                            key: const ValueKey<String>('label-results-ranked'),
                            rows: <_FindRow>[
                              for (final (index, (drink, badge))
                                  in ranked.indexed)
                                _FindRow(
                                  drink: drink,
                                  // One find has nothing to be placed among.
                                  place: ranked.length > 1 ? index + 1 : null,
                                  badge: badge,
                                  saved: saved.contains(drink.id),
                                  onTap: () => onSelect(drink),
                                ),
                            ],
                          ),
                        if (unjudged.isNotEmpty) ...<Widget>[
                          if (ranked.isNotEmpty)
                            const SizedBox(height: AppSpacing.xxl),
                          const Text(
                            labelResultsUnjudgedNote,
                            key: ValueKey<String>('label-results-unjudged'),
                            style: AppTextStyles.sheetBody,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _Rows(
                            rows: <_FindRow>[
                              for (final drink in unjudged)
                                _FindRow(
                                  drink: drink,
                                  place: null,
                                  badge: null,
                                  saved: saved.contains(drink.id),
                                  onTap: () => onSelect(drink),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page when the photos gave no drink: what happened and what to do,
/// with 더 찍기 and 검색 in the header above it.
class _NothingFound extends StatelessWidget {
  const _NothingFound();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.sheetX,
      0,
      AppSpacing.sheetX,
      AppSpacing.massive,
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          labelResultsNoneTitle,
          textAlign: TextAlign.center,
          style: AppTextStyles.sheetTitle,
        ),
        SizedBox(height: AppSpacing.sm),
        Text(
          labelResultsNoneNote,
          textAlign: TextAlign.center,
          style: AppTextStyles.sheetBody,
        ),
      ],
    ),
  );
}

/// Rows on one white card, a thin line between them.
class _Rows extends StatelessWidget {
  const _Rows({required this.rows, super.key});

  final List<_FindRow> rows;

  @override
  Widget build(BuildContext context) => AppSurface(
    borderRadius: AppRadii.compactCard,
    variant: AppSurfaceVariant.elevated,
    boxShadow: AppShadows.searchResults,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final (index, row) in rows.indexed) ...<Widget>[
          if (index != 0)
            const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: AppColors.borderSubtle,
            ),
          row,
        ],
      ],
    ),
  );
}

/// One find: its place among the ranked, then name and kind · strength,
/// then the face. The best of the finds wears its 1 on the app's wine when
/// its face is the smile.
class _FindRow extends StatelessWidget {
  const _FindRow({
    required this.drink,
    required this.place,
    required this.badge,
    required this.saved,
    required this.onTap,
  });

  final CatalogDrink drink;
  final int? place;
  final TasteFitBadge? badge;
  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final facts = <String>[?drink.styleLabel, ?drink.abvLabel].join(' · ');
    final place = this.place;
    final badge = this.badge;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey<String>('label-find:${drink.id}'),
        canRequestFocus: false,
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Row(
            children: <Widget>[
              const SizedBox(width: AppSpacing.lg),
              if (place != null) ...<Widget>[
                _Place(place, best: place == 1 && badge == TasteFitBadge.star),
                const SizedBox(width: AppSpacing.s10),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            drink.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.menuItemTitle,
                          ),
                        ),
                        if (saved) ...const <Widget>[
                          SizedBox(width: AppSpacing.xs),
                          Icon(
                            Icons.favorite_rounded,
                            key: ValueKey<String>('label-find-saved'),
                            size: AppSizes.iconXs,
                            color: AppColors.actionPrimary,
                            semanticLabel: '저장한 술',
                          ),
                        ],
                      ],
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
              const SizedBox(width: AppSpacing.sm),
              if (badge != null) TasteFitRowBadge(badge),
              const SizedBox(width: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// A find's place among the ranked finds, at the left of its row.
class _Place extends StatelessWidget {
  const _Place(this.place, {required this.best});

  final int place;
  final bool best;

  static const _width = 20.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      child: Center(
        child: best
            ? Container(
                width: _width,
                height: _width,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.actionPrimary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$place',
                  style: AppTextStyles.labelSmall.copyWith(color: Colors.white),
                ),
              )
            : Text('$place', style: AppTextStyles.bodyLarge),
      ),
    );
  }
}
