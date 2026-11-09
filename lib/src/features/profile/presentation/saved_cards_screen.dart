import 'package:flutter/material.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../data/liked_cards_gateway.dart';
import '../data/profile_setup_draft.dart';
import 'widgets/profile_collection_chip_widgets.dart';
import 'widgets/profile_liked_record_widgets.dart';

class SavedCardsScreen extends StatefulWidget {
  const SavedCardsScreen({
    this.gateway,
    this.onUnliked,
    this.onOpenCard,
    this.revision = 0,
    super.key,
  });
  final LikedCardsGateway? gateway;

  /// Called after the server took an unlike or its undo.
  final VoidCallback? onUnliked;

  /// Opens a card by its result id.
  final ValueChanged<String>? onOpenCard;

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

  Future<void> _load({bool more = false}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
      if (!more) {
        _cards = [];
        _total = null;
        _nextOffset = 0;
        _hasMore = false;
      }
    });
    try {
      final gateway = widget.gateway;
      if (gateway == null) throw StateError('좋아요 조회 연결이 필요합니다.');
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
        _nextOffset += page.cards.length;
        _hasMore = page.cards.isNotEmpty && _nextOffset < page.total;
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
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
      // Refresh after confirmed removal so pagination does not skip a row.
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('좋아요를 취소했어요.'),
            action: SnackBarAction(
              label: '되돌리기',
              onPressed: () => _undoUnlike(gateway, card),
            ),
          ),
        );
    } catch (_) {
      if (!mounted || widget.gateway != gateway) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('좋아요를 취소하지 못했어요. 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) setState(() => _removing.remove(card.id));
    }
  }

  /// Likes the card again at its old time, so it returns to its place.
  Future<void> _undoUnlike(LikedCardsGateway gateway, LikedCard card) async {
    try {
      await gateway.like(card.id, likedAt: card.likedAt);
      widget.onUnliked?.call();
      if (mounted && widget.gateway == gateway) await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('되돌리지 못했어요. 다시 시도해주세요.')));
    }
  }

  @override
  Widget build(BuildContext context) => AppPageScrollView(
    bottomPadding: AppSpacing.xxxl,
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
                ProfileCollectionFilterChip(
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
                style: AppTextStyles.bodySmall,
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  _latestFirst = !_latestFirst;
                  _load();
                },
                child: Text(_latestFirst ? '최신순' : '오래된순'),
              ),
            ],
          ),
        ),
        if (_loading)
          const LinearProgressIndicator(semanticsLabel: '좋아요한 카드 불러오는 중'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
          child: Column(
            children: [
              if (!_loading && !_failed && _cards.isEmpty)
                const ProfileCollectionEmptyState(
                  icon: Icons.favorite_border_rounded,
                  message: '이 주종에서 좋아요한 술결 카드가 아직 없어요.',
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
              if (_failed)
                TextButton(
                  onPressed: () => _load(more: _cards.isNotEmpty),
                  child: const Text('좋아요한 카드를 불러오지 못했어요. 다시 시도'),
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
