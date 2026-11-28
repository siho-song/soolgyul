import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/catalog/drink_type.dart';
import '../../../design/app_layout.dart';
import '../../../design/app_tokens.dart';
import '../../../widgets/app_filter_chip.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_state_view.dart';
import '../../../widgets/app_tap_slop.dart';
import '../../catalog/data/catalog_drink.dart';
import '../../recording/presentation/widgets/drink_search_results.dart';
import '../../taste_fit/data/saved_drinks_gateway.dart';
import '../../taste_fit/data/taste_fit_gateway.dart';
import '../../taste_fit/data/taste_fit_verdict.dart';
import '../../taste_fit/presentation/widgets/taste_fit_badge.dart';

/// 저장한 술: the bottles the reader saved from the fit page, newest first,
/// listed like search results. The chips over the list keep the bottles of
/// one 주종. Each row carries the face the bottle gets from the reader's
/// cards as they stand now, not the one it had when it was saved. A row
/// opens the bottle's fit page, where the heart takes it out again.
class SavedDrinksScreen extends StatefulWidget {
  const SavedDrinksScreen({
    required this.onOpen,
    this.gateway,
    this.tasteFitGateway,
    this.revision = 0,
    this.recordsRevision = 0,
    super.key,
  });

  /// `null` shows an empty list (previews and tests).
  final SavedDrinksGateway? gateway;
  final ValueChanged<CatalogDrink> onOpen;

  /// Judges the rows against the reader's cards; `null` shows no faces.
  final TasteFitGateway? tasteFitGateway;

  /// Changes when a bottle was saved or taken out on its fit page, so the
  /// list loads again.
  final int revision;

  /// Changes when a record was saved. The faces are drawn from the reader's
  /// cards, so the rows on screen ask for theirs again.
  final int recordsRevision;

  @override
  State<SavedDrinksScreen> createState() => _SavedDrinksScreenState();
}

class _SavedDrinksScreenState extends State<SavedDrinksScreen> {
  List<CatalogDrink>? _drinks;
  int _total = 0;

  /// The 주종 whose bottles are listed; `null` lists them all.
  DrinkType? _type;

  /// What the load failed with; null while it has not.
  Object? _loadError;
  bool _loadingMore = false;

  /// What the last next page failed with; null once a page has come.
  Object? _moreError;
  int _request = 0;

  /// The face of each judged bottle. Old faces stay until new ones arrive.
  Map<String, TasteFitBadge> _badges = const <String, TasteFitBadge>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SavedDrinksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gateway != oldWidget.gateway ||
        widget.revision != oldWidget.revision) {
      _load();
    } else if (widget.tasteFitGateway != oldWidget.tasteFitGateway ||
        widget.recordsRevision != oldWidget.recordsRevision) {
      unawaited(_judge(_drinks ?? const <CatalogDrink>[]));
    }
  }

  /// Asks for the faces of [drinks] as the reader's cards stand now. A call
  /// that fails leaves the rows as they are.
  Future<void> _judge(List<CatalogDrink> drinks) async {
    final gateway = widget.tasteFitGateway;
    if (gateway == null || drinks.isEmpty) return;
    final request = _request;
    try {
      final response = await gateway.judge(<String>[
        for (final drink in drinks) drink.id,
      ]);
      if (!mounted || request != _request) return;
      setState(() {
        // A reader without cards has no faces at all.
        _badges = response.hasCards
            ? <String, TasteFitBadge>{
                ..._badges,
                for (final verdict in response.verdicts.values)
                  verdict.productId: verdict.badge,
              }
            : const <String, TasteFitBadge>{};
      });
    } on TasteFitGatewayException {
      // The rows stay as they are.
    }
  }

  Future<void> _load() async {
    final gateway = widget.gateway;
    final request = ++_request;
    if (gateway == null) {
      setState(() => _drinks = const <CatalogDrink>[]);
      return;
    }
    setState(() {
      _loadError = null;
      _moreError = null;
      _loadingMore = false;
    });
    try {
      final page = await gateway.fetch();
      if (!mounted || request != _request) return;
      setState(() {
        _drinks = page.drinks;
        _total = page.total;
      });
      unawaited(_judge(page.drinks));
      _fillChosenType();
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _drinks = null;
        _loadError = error;
      });
    }
  }

  bool get _hasMore => (_drinks?.length ?? 0) < _total;

  /// The 주종 a bottle is listed under: the catalog's own key for it, which
  /// a rosé carries too, and without one the category it was given.
  static DrinkType? _typeOf(CatalogDrink drink) =>
      DrinkType.fromKey(drink.categoryKey) ?? drink.category.type;

  void _choose(DrinkType? type) {
    setState(() => _type = type);
    _fillChosenType();
  }

  /// The bottles of one 주종 are picked out of the pages that have come, so
  /// with one chosen the pages left are asked for one after another: a
  /// bottle saved long ago is not missing from its 주종. A page that fails
  /// stops it.
  void _fillChosenType() {
    if (_type != null && _hasMore) unawaited(_loadMore());
  }

  /// The next page; a failure leaves the rows shown and asks again the next
  /// time the end is reached.
  Future<void> _loadMore() async {
    final gateway = widget.gateway;
    final shown = _drinks;
    if (gateway == null || shown == null || _loadingMore || !_hasMore) return;
    final request = _request;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await gateway.fetch(offset: shown.length);
      if (!mounted || request != _request) return;
      setState(() {
        // A page that brings nothing ends the list, whatever the total says.
        _total = page.drinks.isEmpty ? shown.length : page.total;
        _drinks = <CatalogDrink>[...shown, ...page.drinks];
      });
      unawaited(_judge(page.drinks));
    } catch (error) {
      // Shown rows stay.
      if (mounted && request == _request) _moreError = error;
    } finally {
      if (mounted && request == _request) setState(() => _loadingMore = false);
    }
    if (mounted && request == _request && _moreError == null) {
      _fillChosenType();
    }
  }

  /// The row's right end: the bottle's face, when it has one, then the
  /// chevron.
  Widget _trailing(CatalogDrink drink) {
    const chevron = AppIcon(
      AppIconAsset.next,
      size: AppSizes.iconMd,
      color: AppColors.textSecondary,
    );
    final badge = _badges[drink.id];
    if (badge == null || badge == TasteFitBadge.noInfo) return chevron;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TasteFitRowBadge(badge),
        const SizedBox(width: AppSpacing.sm),
        chevron,
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _filters(),
      const SizedBox(height: AppSpacing.xl),
      Expanded(child: _list()),
    ],
  );

  /// 전체 and one chip for each 주종, as over 나의 용어 사전.
  Widget _filters() => AppTapSlop(
    slop: AppFilterChip.rowTapSlop,
    along: Axis.horizontal,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
      child: Row(
        children: <Widget>[
          for (final (type, label) in <(DrinkType?, String)>[
            (null, '전체'),
            for (final type in DrinkType.values) (type, type.label),
          ]) ...<Widget>[
            AppFilterChip(
              key: ValueKey<String>(
                'saved-drinks-filter-${type?.key ?? 'all'}',
              ),
              label: label,
              selected: _type == type,
              onPressed: () => _choose(type),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    ),
  );

  Widget _list() {
    final all = _drinks;
    if (_loadError case final error?) {
      return Center(
        child: AppErrorView(
          title: '저장한 술을 불러오지 못했어요',
          error: error,
          onRetry: _load,
        ),
      );
    }
    if (all == null) return const Center(child: AppLoadingView());
    final type = _type;
    final drinks = type == null
        ? all
        : <CatalogDrink>[
            for (final drink in all)
              if (_typeOf(drink) == type) drink,
          ];
    if (drinks.isEmpty && _hasMore) {
      // Its bottles may be on a page that has not come yet.
      return Center(
        child: switch (_moreError) {
          final error? when !_loadingMore => AppErrorView(
            title: '저장한 술을 불러오지 못했어요',
            error: error,
            onRetry: _loadMore,
          ),
          _ => const AppLoadingView(),
        },
      );
    }
    if (drinks.isEmpty) {
      // The same words whether nothing is saved or nothing of this 주종.
      return const Center(
        child: AppEmptyView(
          icon: AppIconAsset.search,
          message: '저장한 술이 아직 없어요.\n내게 맞는 술 찾기에서 하트를 눌러 담아 보세요.',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!AppLayout.isViewportReady(constraints)) {
          return const SizedBox.shrink();
        }
        final horizontalPadding = AppScreenLayout.fromConstraints(
          constraints,
        ).horizontalPadding;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            AppSpacing.sm,
          ),
          // The panel is as tall as its rows; the page scrolls it and asks
          // for the next page near its end.
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (_hasMore && isNearScrollEnd(notification)) _loadMore();
              return false;
            },
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              // Room for the panel's shadow.
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: DrinkSearchResults(
                key: const ValueKey<String>('saved-drinks-list'),
                drinks: List<DrinkSelection>.unmodifiable(
                  drinks.map(DrinkSelection.catalogMatch),
                ),
                selectedDrink: null,
                onDrinkSelected: (selection) =>
                    widget.onOpen(selection.catalogDrink),
                trailingBuilder: _trailing,
                loadingMore: _loadingMore,
              ),
            ),
          ),
        );
      },
    );
  }
}
