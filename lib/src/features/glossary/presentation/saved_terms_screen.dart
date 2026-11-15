import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/async_shown.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_filter_chip.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../../../widgets/app_snack_bar.dart';
import '../../../widgets/app_state_view.dart';
import '../../../widgets/app_surface.dart';
import '../../../widgets/app_tap_slop.dart';
import '../../../widgets/kept_text.dart';
import '../data/saved_terms.dart';
import '../data/saved_terms_provider.dart';

/// 나의 용어 사전: the terms the reader saved from help balloons, newest
/// first, each with its explanation. The chips keep the terms of one drink,
/// or those every drink shares; a term's save mark takes it out.
class SavedTermsScreen extends ConsumerStatefulWidget {
  const SavedTermsScreen({super.key});

  @override
  ConsumerState<SavedTermsScreen> createState() => _SavedTermsScreenState();
}

class _SavedTermsScreenState extends ConsumerState<SavedTermsScreen> {
  /// `null` shows every term.
  TermDrink? _drink;
  final Set<String> _removing = <String>{};

  Future<void> _setSaved(SavedTerm term, {required bool saved}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final terms = ref.read(savedTermsProvider.notifier);
    setState(() => _removing.add(term.key));
    try {
      await terms.setSaved(term.key, saved: saved);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          saved
              ? appSnackBar('나의 용어 사전에 다시 담았어요.', success: true)
              : appSnackBar(
                  '나의 용어 사전에서 뺐어요.',
                  actionLabel: '실행 취소',
                  onAction: () => _setSaved(term, saved: true),
                ),
        );
    } catch (_) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(appSnackBar('저장을 변경하지 못했어요. 다시 시도해 주세요.'));
    } finally {
      if (mounted) setState(() => _removing.remove(term.key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedTermsProvider);
    final all = shownValue(saved);
    final shown = all == null
        ? const <SavedTerm>[]
        : <SavedTerm>[
            for (final term in all)
              if (_drink == null || term.drinks.contains(_drink)) term,
          ];
    return AppPageScrollView(
      bottomPadding: AppSpacing.xxxl,
      onRefresh: () => ref.refresh(savedTermsProvider.future),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTapSlop(
            slop: AppFilterChip.rowTapSlop,
            along: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenX,
              ),
              child: Row(
                children: <Widget>[
                  for (final (drink, label) in <(TermDrink?, String)>[
                    (null, '전체'),
                    for (final drink in TermDrink.values) (drink, drink.label),
                  ]) ...<Widget>[
                    AppFilterChip(
                      key: ValueKey<String>(
                        'saved-terms-filter-${drink?.wire ?? 'all'}',
                      ),
                      label: label,
                      selected: _drink == drink,
                      onPressed: () => setState(() => _drink = drink),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (all != null) ...<Widget>[
                  Text('총 ${shown.length}개', style: AppTextStyles.body),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (all == null && saved.hasError)
                  AppErrorView(
                    title: '나의 용어 사전을 불러오지 못했어요',
                    onRetry: () => ref.invalidate(savedTermsProvider),
                  )
                else if (all == null)
                  const AppLoadingView(semanticsLabel: '나의 용어 사전 불러오는 중')
                else if (shown.isEmpty)
                  AppEmptyView(
                    message: all.isEmpty
                        ? '저장한 용어가 아직 없어요.\n'
                              '밑줄 친 단어의 도움말에서 저장 버튼을 눌러 담아 보세요.'
                        : '${_drink!.label}에 저장한 용어가 없어요.',
                  ),
                for (final term in shown) ...<Widget>[
                  _SavedTermCard(
                    key: ValueKey<String>('saved-term-${term.key}'),
                    term: term,
                    onRemove: _removing.contains(term.key)
                        ? null
                        : () => _setSaved(term, saved: false),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One saved term: its name and kind as the balloon heads them, the drinks
/// it belongs to, and the explanation.
class _SavedTermCard extends StatelessWidget {
  const _SavedTermCard({required this.term, required this.onRemove, super.key});

  final SavedTerm term;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final filedUnder = <String>[
      term.kind,
      for (final drink in TermDrink.values)
        if (term.drinks.contains(drink)) drink.label,
    ].join(' · ');
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  term.label,
                  style: AppTextStyles.cardTitle.copyWith(
                    color: AppColors.actionPrimary,
                  ),
                ),
              ),
              AppIconButton(
                onPressed: onRemove,
                tooltip: '나의 용어 사전에서 빼기',
                size: AppIconButtonSize.small,
                child: const Icon(
                  Icons.bookmark_rounded,
                  size: 20,
                  color: AppColors.actionPrimary,
                ),
              ),
            ],
          ),
          Text(filedUnder, style: AppTextStyles.caption),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: KeptText(term.description, style: AppTextStyles.modalBody),
          ),
        ],
      ),
    );
  }
}
