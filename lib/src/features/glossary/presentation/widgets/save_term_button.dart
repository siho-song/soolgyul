import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design/app_tokens.dart';
import '../../../../widgets/app_icon_button.dart';
import '../../../../core/async_shown.dart';
import '../../../../widgets/app_snack_bar.dart';
import '../../data/saved_terms_provider.dart';

/// The save button of a help balloon for the term [termKey], or `null` when
/// the balloon has none: the explanation is not a dictionary term, or nobody
/// is signed in to keep it for.
Widget? saveTermAction(BuildContext context, String? termKey) {
  if (termKey == null) return null;
  final ProviderContainer providers;
  try {
    providers = ProviderScope.containerOf(context, listen: false);
  } on StateError {
    // A screen shown on its own, outside the app, keeps nothing.
    return null;
  }
  if (providers.read(savedTermsGatewayProvider)?.accountId == null) return null;
  return SaveTermButton(termKey: termKey);
}

/// The save mark in a help balloon: filled while the term is in 나의 용어
/// 사전.
/// A touch saves the term, or takes it out, and says where it is kept.
class SaveTermButton extends ConsumerStatefulWidget {
  const SaveTermButton({required this.termKey, super.key});

  final String termKey;

  @override
  ConsumerState<SaveTermButton> createState() => _SaveTermButtonState();
}

class _SaveTermButtonState extends ConsumerState<SaveTermButton> {
  /// What the reader just chose, shown until the server answers.
  bool? _asked;

  Future<void> _toggle(bool saved) async {
    final next = !saved;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _asked = next);
    String notice;
    try {
      await ref
          .read(savedTermsProvider.notifier)
          .setSaved(widget.termKey, saved: next);
      notice = next ? '나의 용어 사전에 저장했어요. 내 정보에서 다시 볼 수 있어요.' : '나의 용어 사전에서 뺐어요.';
    } catch (error) {
      notice = failureLine(error, '저장을 변경하지 못했어요. 다시 시도해 주세요.');
    }
    // The balloon may have closed meanwhile; the notice still shows.
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(appSnackBar(notice, success: notice.startsWith('나의')));
    if (mounted) setState(() => _asked = null);
  }

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(savedTermsProvider);
    final loaded = shownValue(terms);
    final known = loaded != null && !terms.isLoading;
    final saved =
        _asked ?? (loaded?.any((term) => term.holds(widget.termKey)) ?? false);
    return AppIconButton(
      key: const ValueKey<String>('term-tooltip-save'),
      onPressed: _asked != null
          ? null
          : terms.hasError
          ? () => ref.invalidate(savedTermsProvider)
          : known
          ? () => _toggle(saved)
          : null,
      tooltip: terms.hasError
          ? '저장 상태 다시 확인'
          : saved
          ? '나의 용어 사전에서 빼기'
          : '나의 용어 사전에 저장',
      size: AppIconButtonSize.mini,
      child: Icon(
        saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        size: 18,
        color: saved ? AppColors.actionPrimary : AppColors.textTertiary,
      ),
    );
  }
}
