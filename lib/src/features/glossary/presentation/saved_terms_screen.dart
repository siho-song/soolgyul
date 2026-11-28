import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/async_shown.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_filter_chip.dart';
import '../../../widgets/app_icon.dart';
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

  /// Takes out what [keys] name and offers to put it back: one term, one
  /// style of a place, or a place with every style saved under it.
  Future<void> _remove(String id, List<String> keys) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final terms = ref.read(savedTermsProvider.notifier);
    setState(() => _removing.add(id));
    try {
      // Taking a place out takes its styles with it: one request does.
      await terms.setSaved(id, saved: false);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          appSnackBar(
            '나의 용어 사전에서 뺐어요.',
            actionLabel: '실행 취소',
            onAction: () => _restore(id, keys),
          ),
        );
    } catch (error) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          appSnackBar(failureLine(error, '저장을 변경하지 못했어요. 다시 시도해 주세요.')),
        );
    } finally {
      if (mounted) setState(() => _removing.remove(id));
    }
  }

  Future<void> _restore(String id, List<String> keys) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final terms = ref.read(savedTermsProvider.notifier);
    setState(() => _removing.add(id));
    try {
      for (final key in keys) {
        await terms.setSaved(key, saved: true);
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(appSnackBar('나의 용어 사전에 다시 담았어요.', success: true));
    } catch (error) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          appSnackBar(failureLine(error, '저장을 변경하지 못했어요. 다시 시도해 주세요.')),
        );
    } finally {
      if (mounted) setState(() => _removing.remove(id));
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
                    error: saved.error,
                    onRetry: () => ref.invalidate(savedTermsProvider),
                  )
                else if (all == null)
                  const AppLoadingView(semanticsLabel: '나의 용어 사전 불러오는 중')
                else if (shown.isEmpty)
                  // The same words whether nothing is saved or nothing
                  // under the chosen chip.
                  const AppEmptyView(message: '저장한 용어가 아직 없어요.'),
                for (final term in shown) ...<Widget>[
                  _SavedTermCard(
                    key: ValueKey<String>('saved-term-${term.key}'),
                    term: term,
                    onRemove: _removing.contains(term.key)
                        ? null
                        : () => _remove(term.key, <String>[
                            // What was saved, oldest first, to save again.
                            for (final part in term.parts.reversed) part.key,
                            if (term.own) term.key,
                          ]),
                    onRemovePart: (part) => _removing.contains(part.key)
                        ? null
                        : () => _remove(part.key, <String>[part.key]),
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
/// it belongs to, and the explanation. A place shows its own explanation and
/// then each style the reader saved of it, each with its own save mark.
class _SavedTermCard extends StatelessWidget {
  const _SavedTermCard({
    required this.term,
    required this.onRemove,
    required this.onRemovePart,
    super.key,
  });

  final SavedTerm term;
  final VoidCallback? onRemove;
  final VoidCallback? Function(SavedStyle part) onRemovePart;

  @override
  Widget build(BuildContext context) {
    final filedUnder = <String>[
      term.kind,
      for (final drink in TermDrink.values)
        if (term.drinks.contains(drink)) drink.label,
    ].join(' · ');
    final body = term.parts.isEmpty ? term.description : term.intro;
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
                child: const AppIcon(
                  AppIconAsset.bookmarkFill,
                  size: 20,
                  color: AppColors.actionPrimary,
                ),
              ),
            ],
          ),
          Text(filedUnder, style: AppTextStyles.caption),
          if (body != null && body.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: KeptText(body, style: AppTextStyles.modalBody),
            ),
          ],
          for (final part in term.parts) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: Divider(height: 1, color: AppColors.borderSubtle),
            ),
            Row(
              key: ValueKey<String>('saved-term-part-${part.key}'),
              children: <Widget>[
                Expanded(
                  child: Text(
                    part.label,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AppIconButton(
                  onPressed: onRemovePart(part),
                  tooltip: '${part.label} 설명 빼기',
                  size: AppIconButtonSize.small,
                  child: const AppIcon(
                    AppIconAsset.bookmarkFill,
                    size: 18,
                    color: AppColors.actionPrimary,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: KeptText(part.description, style: AppTextStyles.modalBody),
            ),
          ],
        ],
      ),
    );
  }
}
