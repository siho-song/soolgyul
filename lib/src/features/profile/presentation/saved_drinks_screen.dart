import 'package:flutter/material.dart';

import '../../../design/app_layout.dart';
import '../../../design/app_tokens.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_state_view.dart';
import '../../catalog/data/catalog_drink.dart';
import '../../recording/presentation/widgets/drink_search_results.dart';
import '../../taste_fit/data/saved_drinks_gateway.dart';

/// 저장한 술: the bottles the reader saved from the fit page, newest first,
/// listed like search results. A row opens the bottle's fit page, where the
/// heart takes it out again.
class SavedDrinksScreen extends StatefulWidget {
  const SavedDrinksScreen({
    required this.onOpen,
    this.gateway,
    this.revision = 0,
    super.key,
  });

  /// `null` shows an empty list (previews and tests).
  final SavedDrinksGateway? gateway;
  final ValueChanged<CatalogDrink> onOpen;

  /// Changes when a bottle was saved or taken out on its fit page, so the
  /// list loads again.
  final int revision;

  @override
  State<SavedDrinksScreen> createState() => _SavedDrinksScreenState();
}

class _SavedDrinksScreenState extends State<SavedDrinksScreen> {
  List<CatalogDrink>? _drinks;
  int _total = 0;
  bool _loadFailed = false;
  bool _loadingMore = false;
  int _request = 0;

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
      _loadFailed = false;
      _loadingMore = false;
    });
    try {
      final page = await gateway.fetch();
      if (!mounted || request != _request) return;
      setState(() {
        _drinks = page.drinks;
        _total = page.total;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _drinks = null;
        _loadFailed = true;
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
    } catch (_) {
      // Shown rows stay.
    } finally {
      if (mounted && request == _request) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drinks = _drinks;
    if (_loadFailed) {
      return Center(
        child: AppErrorView(title: '저장한 술을 불러오지 못했어요', onRetry: _load),
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
                loadingMore: _loadingMore,
              ),
            ),
          ),
        );
      },
    );
  }
}
