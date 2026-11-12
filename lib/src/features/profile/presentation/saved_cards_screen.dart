import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_filter_chip.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../data/liked_cards_gateway.dart';
import '../data/profile_setup_draft.dart';
import 'widgets/profile_liked_record_widgets.dart';
import '../../../widgets/app_state_view.dart';
import '../../../widgets/app_snack_bar.dart';

class SavedCardsScreen extends StatefulWidget {
  const SavedCardsScreen({
    this.gateway,
    this.onUnliked,
    this.onOpenCard,
    this.onChangedAway,
    this.revision = 0,
    super.key,
  });
  final LikedCardsGateway? gateway;

  /// Called after the server took an unlike or its undo.
  final VoidCallback? onUnliked;

  /// Opens a card by its result id.
  final ValueChanged<String>? onOpenCard;

  /// Called when an undo lands after this screen was left: the screen shown
  /// next is another one, which reloads when [revision] changes.
  final VoidCallback? onChangedAway;

  /// Changes when a like or a record changed elsewhere (on an opened card),
  /// so the list reloads in its current filter and order.
  final int revision;

  @override
  State<SavedCardsScreen> createState() => _SavedCardsScreenState();
}

class _SavedCardsScreenState extends State<SavedCardsScreen> {
  String? _category;
  bool _latestFirst = true;
  bool _loading = false;
  bool _failed = false;
  int _request = 0;
  int? _total;
  int _nextOffset = 0;
  bool _hasMore = false;
  List<LikedCard> _cards = [];
  final Set<String> _removing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SavedCardsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gateway != oldWidget.gateway ||
        widget.revision != oldWidget.revision) {
      _load();
    }
  }

  /// Pulled down: the cards on screen stay until the new first page
  /// arrives, and stay if it does not.
  Future<void> _refresh() => _load(refresh: _cards.isNotEmpty);

  Future<void> _load({bool more = false, bool refresh = false}) async {
    final request = ++_request;
    setState(() {
      _loading = !refresh;
      _failed = false;
      if (!more && !refresh) {
        _cards = [];
        _total = null;
        _nextOffset = 0;
        _hasMore = false;
      }
    });
    try {
      final gateway = widget.gateway;
      if (gateway == null) throw StateError('no liked-cards gateway');
      final page = await gateway.fetch(
        category: _category,
        latestFirst: _latestFirst,
        offset: more ? _nextOffset : 0,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _cards = <String, LikedCard>{
          if (more)
            for (final card in _cards) card.id: card,
          for (final card in page.cards) card.id: card,
        }.values.toList();
        _total = page.total;
        _nextOffset = (more ? _nextOffset : 0) + page.cards.length;
        _hasMore = page.cards.isNotEmpty && _nextOffset < page.total;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      if (refresh) {
        showAppSnackBar(context, '카드를 새로 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
      } else {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _unlike(LikedCard card) async {
    if (_removing.contains(card.id) || widget.gateway == null) return;
    final gateway = widget.gateway!;
    setState(() => _removing.add(card.id));
    try {
      await gateway.unlike(card.id);
      widget.onUnliked?.call();
      if (!mounted || widget.gateway != gateway) return;
      // The row leaves where it stands, after the server took it.
      final index = _cards.indexWhere((shown) => shown.id == card.id);
      final view = (_category, _latestFirst);
      if (index >= 0) _shift(-1, () => _cards.removeAt(index));
      showAppSnackBar(
        context,
        '보관을 취소했어요.',
        success: true,
        actionLabel: '실행 취소',
        onAction: () => _undoUnlike(gateway, card, index, view),
      );
    } catch (_) {
      if (!mounted || widget.gateway != gateway) return;
      showAppSnackBar(context, '처리에 실패했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _removing.remove(card.id));
    }
  }

  /// Changes the rows shown with [change] and moves the count and the next
  /// page's start by [by], so the next page neither skips nor repeats a row.
  void _shift(int by, VoidCallback change) {
    setState(() {
      _cards = List<LikedCard>.of(_cards);
      change();
      if (_total case final total?) _total = total + by;
      _nextOffset += by;
    });
  }

  /// Likes the card again at its old time, so it returns to its place: the
  /// [index] it left in the same [view], or wherever a reload puts it when
  /// the list was filtered or sorted since.
  Future<void> _undoUnlike(
    LikedCardsGateway gateway,
    LikedCard card,
    int index,
    (String?, bool) view,
  ) async {
    try {
      // Read before the await: the reader may leave while the like is sent.
      final (onUnliked, onChangedAway) = (
        widget.onUnliked,
        widget.onChangedAway,
      );
      await gateway.like(card.id, likedAt: card.likedAt);
      onUnliked?.call();
      if (!mounted) {
        onChangedAway?.call();
      } else if (widget.gateway == gateway) {
        final inPlace =
            index >= 0 &&
            view == (_category, _latestFirst) &&
            !_cards.any((shown) => shown.id == card.id);
        if (inPlace) {
          _shift(1, () => _cards.insert(math.min(index, _cards.length), card));
        } else {
          await _load(refresh: true);
        }
      }
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, '다시 되돌리지 못했어요. 잠시 후 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) => AppPageScrollView(
    bottomPadding: AppSpacing.xxxl,
    onRefresh: _refresh,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
          child: Row(
            children: [
              for (final entry in <String?, String>{
                null: '전체',
                for (final interest in DrinkInterest.values)
                  interest.wireKey: interest.label,
              }.entries) ...[
                AppFilterChip(
                  label: entry.value,
                  selected: _category == entry.key,
                  onPressed: () {
                    _category = entry.key;
                    _load();
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
          child: Row(
            children: [
              Text(
                _total == null ? '총 —개' : '총 $_total개',
                style: AppTextStyles.body,
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  _latestFirst = !_latestFirst;
                  _load();
                },
                child: Text(_latestFirst ? '최신순' : '과거순'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
          child: Column(
            children: [
              // Words alone: the cards are kept with a heart, and a
              // bookmark here would read as the saved posts.
              if (!_loading && !_failed && _cards.isEmpty)
                AppEmptyView(
                  message: _category == null
                      ? '보관한 술결 카드가 없어요.'
                      : '선택한 주종에 보관된 술결 카드가 없어요.',
                ),
              for (final card in _cards) ...[
                LikedRecordCard(
                  key: ValueKey(card.id),
                  record: card,
                  onUnlike: _removing.contains(card.id)
                      ? null
                      : () => _unlike(card),
                  onOpen: switch ((card.resultId, widget.onOpenCard)) {
                    (final String resultId, final open?) => () => open(
                      resultId,
                    ),
                    _ => null,
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (_loading)
                AppLoadingView(
                  compact: _cards.isNotEmpty,
                  semanticsLabel: '보관한 술결 카드 불러오는 중',
                ),
              if (_failed && _cards.isEmpty)
                AppErrorView(title: '보관한 술결 카드를 불러오지 못했어요', onRetry: _load),
              // Rows already shown stay; only the next page is asked again.
              if (_failed && _cards.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: AppCardError(
                    message: '카드를 더 불러오지 못했어요.',
                    onRetry: () => _load(more: true),
                  ),
                ),
              if (!_failed && !_loading && _hasMore)
                TextButton(
                  onPressed: () => _load(more: true),
                  child: const Text('더 보기'),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
