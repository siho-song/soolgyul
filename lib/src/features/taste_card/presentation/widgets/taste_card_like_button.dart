import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../widgets/app_top_bar.dart';
import '../../../profile/data/liked_cards_gateway.dart';

/// The heart at the right end of a saved card's header. Only mounted for a
/// saved, owned result; anonymous previews cannot be liked.
class TasteCardLikeButton extends StatefulWidget {
  const TasteCardLikeButton({
    required this.cardId,
    required this.gateway,
    this.isActive = true,
    this.onChanged,
    super.key,
  });
  final String cardId;
  final LikedCardsGateway gateway;
  final bool isActive;

  /// Called after the server took a like or an unlike.
  final VoidCallback? onChanged;

  @override
  State<TasteCardLikeButton> createState() => _TasteCardLikeButtonState();
}

class _TasteCardLikeButtonState extends State<TasteCardLikeButton> {
  bool? _liked;
  bool _busy = false;
  bool _loadFailed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _load();
  }

  @override
  void didUpdateWidget(TasteCardLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cardId != oldWidget.cardId ||
        widget.gateway != oldWidget.gateway ||
        widget.isActive != oldWidget.isActive) {
      _request++;
      _liked = null;
      _loadFailed = false;
      _busy = false;
      if (widget.isActive) _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _loadFailed = false;
    });
    try {
      final liked = await widget.gateway.isLiked(widget.cardId);
      if (mounted && request == _request) setState(() => _liked = liked);
    } catch (_) {
      if (mounted && request == _request) setState(() => _loadFailed = true);
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _toggle() async {
    if (_busy || _liked == null) return;
    final request = ++_request;
    final next = !_liked!;
    setState(() => _busy = true);
    try {
      if (next) {
        await widget.gateway.like(widget.cardId);
      } else {
        await widget.gateway.unlike(widget.cardId);
      }
      widget.onChanged?.call();
      if (mounted && request == _request) setState(() => _liked = next);
    } catch (_) {
      if (mounted && request == _request) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('좋아요를 변경하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liked = _liked == true;
    return AppTopBarMaterialAction(
      key: const ValueKey('taste-card-like-button'),
      icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      color: liked ? AppColors.actionPrimary : AppColors.textPrimary,
      onPressed: !widget.isActive || _busy
          ? null
          : _loadFailed
          ? _load
          : _toggle,
      tooltip: _loadFailed
          ? '보관 상태 다시 확인'
          : _liked == null
          ? '보관 여부 확인 중'
          : liked
          ? '보관 취소'
          : '보관하기',
    );
  }
}
