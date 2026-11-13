import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/async_shown.dart';
import '../../../design/app_tokens.dart';
import '../../../widgets/kept_text.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../data/home_providers.dart';
import '../data/taste_letters.dart';
import 'soolgyul_letters_detail_sections.dart';
import '../../../widgets/app_state_view.dart';

/// The letters detail. Without a gateway it shows the design placeholder.
class SoolgyulLettersDetailScreen extends ConsumerStatefulWidget {
  const SoolgyulLettersDetailScreen({super.key, this.onOpenCard});

  /// Opens the saved card of the record behind a 취향이 바뀐 순간 moment.
  final ValueChanged<String>? onOpenCard;

  @override
  ConsumerState<SoolgyulLettersDetailScreen> createState() =>
      _SoolgyulLettersDetailScreenState();
}

class _SoolgyulLettersDetailScreenState
    extends ConsumerState<SoolgyulLettersDetailScreen> {
  @override
  Widget build(BuildContext context) {
    if (ref.watch(tasteLettersGatewayProvider) == null) {
      return _page(_dataSections(const TasteLettersSnapshot()));
    }
    final letters = ref.watch(tasteLettersProvider);
    final loaded = shownValue(letters);
    return _page(
      loaded != null
          ? _dataSections(loaded)
          : <Widget>[
              letters.hasError && !letters.isLoading
                  ? AppErrorView(
                      title: '취향 조각을 불러오지 못했어요',
                      onRetry: () => ref.invalidate(tasteLettersProvider),
                    )
                  : const AppLoadingView(semanticsLabel: '취향 조각을 불러오는 중'),
            ],
    );
  }

  Widget _page(List<Widget> sections) => MainTabScrollView(
    topPadding: AppSpacing.lg,
    bottomPadding: AppSpacing.xxxl,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const KeptText(
          '내 취향의 결을 담은 4가지 조각이에요.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body,
        ),
        const SizedBox(height: AppSpacing.xl),
        ...sections,
        const SizedBox(height: AppSpacing.xxl),
      ],
    ),
  );

  List<Widget> _dataSections(TasteLettersSnapshot snapshot) {
    final state = snapshot.state ?? const TasteLettersState(axes: {});
    final revealed = state.revealed;
    final hidden = state.hidden;
    return <Widget>[
      SoolgyulOverviewPanel(state: state),
      if (revealed.isNotEmpty) ...<Widget>[
        const SizedBox(height: AppSpacing.xxxl),
        const LettersSectionIntroduction(
          title: '발견한 취향 조각',
          description: '기록이 쌓이며 선명해진 나만의 입맛 기준이에요.',
        ),
        const SizedBox(height: AppSpacing.xl),
        for (var index = 0; index < revealed.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(height: AppSpacing.md),
          LetterMeaningPanel(
            meaning: meaningForAxis(
              revealed[index],
              TasteLetterPole.of(state.letterOf(revealed[index]))!,
            ),
            share: TasteLetterShareGauge(
              axis: revealed[index],
              state: state.of(revealed[index]),
            ),
          ),
        ],
      ],
      if (hidden.isNotEmpty) ...<Widget>[
        const SizedBox(height: AppSpacing.xxxl),
        LettersSectionIntroduction(
          title: '채워질 취향 조각',
          description: hiddenSectionDescription(hidden.length),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final (index, axis) in hidden.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: AppSpacing.md),
          HiddenAxisPanel(
            axis: axis,
            tileKey: ValueKey<String>('unknown-letter-$index'),
          ),
        ],
      ],
      const SizedBox(height: AppSpacing.xxxl),
      const LettersSectionIntroduction(
        title: '취향의 변화',
        description: '취향 조각이 처음 열리거나 달라진 순간이에요.',
      ),
      const SizedBox(height: AppSpacing.xl),
      TasteLetterChangeList(
        changes: snapshot.changes,
        limit: 1,
        onOpenCard: widget.onOpenCard,
        onShowAll: () => showTasteLetterJourneySheet(
          context,
          snapshot.changes,
          onOpenCard: widget.onOpenCard,
        ),
      ),
    ];
  }
}
