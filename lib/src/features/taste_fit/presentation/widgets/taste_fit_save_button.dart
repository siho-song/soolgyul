import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../widgets/app_snack_bar.dart';
import '../../../../widgets/app_top_bar.dart';
import '../../data/saved_drinks_gateway.dart';
import '../../data/taste_fit_verdict.dart';

/// The heart at the right end of a bottle's fit page: filled while the
/// bottle is among 저장한 술.
class TasteFitSaveButton extends StatefulWidget {
  const TasteFitSaveButton({
    required this.drinkId,
    required this.gateway,
    this.badge,
    this.onChanged,
    super.key,
  });

  final String drinkId;
  final SavedDrinksGateway gateway;

  /// The verdict the page shows for the bottle now; kept with the save.
  final TasteFitBadge? badge;

  /// Called after the server took a save or its removal.
  final VoidCallback? onChanged;

  @override
  State<TasteFitSaveButton> createState() => _TasteFitSaveButtonState();
}

class _TasteFitSaveButtonState extends State<TasteFitSaveButton> {
  bool? _saved;
  bool _busy = false;
  bool _loadFailed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TasteFitSaveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.drinkId != oldWidget.drinkId ||
        widget.gateway != oldWidget.gateway) {
      _saved = null;
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _loadFailed = false;
    });
    try {
      final saved = await widget.gateway.isSaved(widget.drinkId);
      if (mounted && request == _request) setState(() => _saved = saved);
    } catch (_) {
      if (mounted && request == _request) setState(() => _loadFailed = true);
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _toggle() async {
    if (_busy || _saved == null) return;
    final request = ++_request;
    final next = !_saved!;
    setState(() => _busy = true);
    try {
      if (next) {
        await widget.gateway.save(widget.drinkId, badge: widget.badge);
      } else {
        await widget.gateway.unsave(widget.drinkId);
      }
      widget.onChanged?.call();
      if (mounted && request == _request) setState(() => _saved = next);
    } catch (_) {
      if (mounted && request == _request) {
        showAppSnackBar(context, '저장을 변경하지 못했어요. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved == true;
    return AppTopBarMaterialAction(
      key: const ValueKey<String>('taste-fit-save-button'),
      icon: saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      color: saved ? AppColors.actionPrimary : AppColors.textPrimary,
      onPressed: _busy
          ? null
          : _loadFailed
          ? _load
          : _toggle,
      tooltip: _loadFailed
          ? '저장 상태 다시 확인'
          : _saved == null
          ? '저장 여부 확인 중'
          : saved
          ? '저장 취소'
          : '술 저장하기',
    );
  }
}
