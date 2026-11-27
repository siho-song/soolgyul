import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/app_layout.dart';
import '../../../design/app_tokens.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_state_view.dart';
import '../../catalog/data/catalog_drink.dart';
import '../../recording/presentation/widgets/drink_search_results.dart';
import '../../taste_fit/data/saved_drinks_gateway.dart';
import '../../taste_fit/data/taste_fit_gateway.dart';
import '../../taste_fit/data/taste_fit_verdict.dart';
import '../../taste_fit/presentation/widgets/taste_fit_badge.dart';

/// 저장한 술: the bottles the reader saved from the fit page, newest first,
/// listed like search results. Each row carries the face the bottle gets
/// from the reader's cards as they stand now, not the one it had when it was
/// saved. A row opens the bottle's fit page, where the heart takes it out
/// again.
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

  /// What the load failed with; null while it has not.
  Object? _loadError;
  bool _loadingMore = false;
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
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _drinks = null;
        _loadError = error;
      });
    }
  }

  bool get _hasMore => (_drinks?.length ?? 0) < _total;

  /// The next page; a failure leaves the rows shown and asks again the next
  /// time the end is reached.
  Future<void> _loadMore() async {
    final gateway = widget.gateway;
    final shown = _drinks;
    if (gateway == null || shown == null || _loadingMore || !_hasMore) return;
    final request = _request;
    setState(() => _loadingMore = true);
    try {
      final page = await gateway.fetch(offset: shown.length);
      if (!mounted || request != _request) return;
      setState(() {
        // A page that brings nothing ends the list, whatever the total says.
        _total = page.drinks.isEmpty ? shown.length : page.total;
        _drinks = <CatalogDrink>[...shown, ...page.drinks];
      });
      unawaited(_judge(page.drinks));
    } catch (_) {
      // Shown rows stay.
    } finally {
      if (mounted && request == _request) setState(() => _loadingMore = false);
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
  Widget build(BuildContext context) {
    final drinks = _drinks;
    if (_loadError case final error?) {
      return Center(
        child: AppErrorView(
          title: '저장한 술을 불러오지 못했어요',
          error: error,
          onRetry: _load,
        ),
      );
    }
    if (drinks == null) return const Center(child: AppLoadingView());
    if (drinks.isEmpty) {
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
            AppSpacing.md,
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
