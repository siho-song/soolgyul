import 'package:flutter/material.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../data/home_placeholder_content.dart';
import '../data/taste_letters.dart';
import 'soolgyul_letters_detail_sections.dart';

/// The letters detail. Without a gateway it shows the design placeholder.
class SoolgyulLettersDetailScreen extends StatefulWidget {
  const SoolgyulLettersDetailScreen({super.key, this.gateway, this.onOpenCard});

  final TasteLettersGateway? gateway;

  /// Opens the saved card of the record behind a 취향이 바뀐 순간 moment.
  final ValueChanged<String>? onOpenCard;

  @override
  State<SoolgyulLettersDetailScreen> createState() =>
      _SoolgyulLettersDetailScreenState();
}

class _SoolgyulLettersDetailScreenState
    extends State<SoolgyulLettersDetailScreen> {
  Future<TasteLettersSnapshot>? _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.gateway?.load();
  }

  @override
  void didUpdateWidget(SoolgyulLettersDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gateway != oldWidget.gateway) {
      _snapshot = widget.gateway?.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null) return _page(_placeholderSections);
    return FutureBuilder<TasteLettersSnapshot>(
      future: snapshot,
      builder: (context, result) => _page(switch (result.connectionState) {
        ConnectionState.done when result.hasError => _messageSections(
          '취향 조각을 불러오지 못했어요.',
        ),
        ConnectionState.done => _dataSections(
          result.data ?? const TasteLettersSnapshot(),
        ),
        _ => _messageSections('불러오는 중이에요.'),
      }),
    );
  }

  Widget _page(List<Widget> sections) => MainTabScrollView(
    topPadding: AppSpacing.lg,
    bottomPadding: 44,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          '내 취향의 결을 담은 네 조각이에요.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xl),
        ...sections,
        const SizedBox(height: AppSpacing.xxl),
      ],
    ),
  );

  List<Widget> _messageSections(String message) => <Widget>[
    SoolgyulOverviewPanel(message: message),
  ];

  List<Widget> _dataSections(TasteLettersSnapshot snapshot) {
    final state = snapshot.state ?? const TasteLettersState(axes: {});
    final revealed = state.revealed;
    final hidden = state.hidden;
    return <Widget>[
      SoolgyulOverviewPanel(state: state),
      if (revealed.isNotEmpty) ...<Widget>[
        const SizedBox(height: AppSpacing.xxxl),
        const LettersSectionIntroduction(
          title: '드러난 취향 조각',
          description: '기록이 쌓여 선명해진 내 입맛의 기준들이에요',
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
          title: '피어날 취향 조각',
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
        title: '취향이 바뀐 순간',
        description: '조각이 처음 드러나거나 반대쪽으로 넘어간 순간이에요',
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

  List<Widget> get _placeholderSections => <Widget>[
    const SoolgyulOverviewPanel(),
    const SizedBox(height: AppSpacing.xxxl),
    const LettersSectionIntroduction(
      title: '드러난 취향 조각',
      description: '먼저 드러난 두 조각 속에 담긴 내 취향의 결이에요',
    ),
    const SizedBox(height: AppSpacing.xl),
    LetterMeaningPanel(meaning: revealedLetterMeanings[0]),
    const SizedBox(height: AppSpacing.md),
    LetterMeaningPanel(meaning: revealedLetterMeanings[1]),
    const SizedBox(height: AppSpacing.xxxl),
    LettersSectionIntroduction(
      title: '피어날 취향 조각',
      description: hiddenSectionDescription(2),
    ),
    const SizedBox(height: AppSpacing.xl),
    const HiddenAxisPanel(axis: TasteLetterAxis.weight),
    const SizedBox(height: AppSpacing.md),
    const HiddenAxisPanel(axis: TasteLetterAxis.finish),
  ];
}
