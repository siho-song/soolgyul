import '../../../design/app_tokens.dart';
import 'package:flutter/material.dart';

import '../../../core/format/dates.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_term_tooltip.dart';
import '../../../widgets/paper_box.dart';
import '../../../widgets/text_underline.dart';
import '../../recording/presentation/widgets/drink_result_photo.dart';
import 'widgets/taste_card_guide_body.dart';
import 'widgets/taste_card_guide_parts.dart';
import '../data/taste_card_snapshot_view_data.dart';

part 'card/taste_card_actions.dart';
part 'card/taste_card_bite_section.dart';
part 'card/taste_card_common.dart';
part 'card/taste_card_drink_header.dart';
part 'card/taste_card_reason_section.dart';

enum TasteCardLoadState { loading, retryable, failure }

class TasteCardStatusScreen extends StatelessWidget {
  const TasteCardStatusScreen({
    required this.state,
    this.onRetry,
    this.savedCard = false,
    super.key,
  });

  final TasteCardLoadState state;
  final VoidCallback? onRetry;

  /// Whether a saved card is being opened rather than a new one made.
  final bool savedCard;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (state) {
      TasteCardLoadState.loading when savedCard => (
        '술결 카드를 불러오고 있어요',
        '잠시만 기다려 주세요.',
      ),
      _ when savedCard => ('술결 카드를 불러오지 못했어요', '잠시 후 다시 시도해 주세요.'),
      TasteCardLoadState.loading => (
        '나만의 술결을 분석하고 있어요',
        '남겨주신 감각을 바탕으로 다음 잔의 기준을 찾고 있어요.',
      ),
      TasteCardLoadState.retryable => (
        '네트워크 연결이 불안정해요',
        '작성한 내용은 안전하게 보관 중이에요. 다시 시도해 주세요.',
      ),
      TasteCardLoadState.failure => (
        '술결 카드를 완성하지 못했어요',
        '입력한 내용은 저장되어 있어요. 잠시 후 다시 시도해 주세요.',
      ),
    };
    return ColoredBox(
      color: _TasteCardColors.canvas,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (state == TasteCardLoadState.loading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 28),
                    child: CircularProgressIndicator(
                      color: _TasteCardColors.wine,
                    ),
                  ),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: _TasteCardText.headline,
                ),
                const SizedBox(height: 14),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: _TasteCardText.body,
                ),
                if (state != TasteCardLoadState.loading) ...<Widget>[
                  const SizedBox(height: 30),
                  AppButton(label: '다시 시도', onPressed: onRetry),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TasteCardScreen extends StatefulWidget {
  const TasteCardScreen({
    required this.viewData,
    this.onSave,
    this.onOpenApp,
    super.key,
  });

  /// The 저장 button's action; null leaves the button out, as on a saved
  /// card opened again.
  final VoidCallback? onSave;

  /// The card the server wrote.
  final TasteCardSnapshotViewData viewData;

  /// On the web the card ends the onboarding: instead of the save button a
  /// bar fixed at the bottom sends the visitor to the app.
  final VoidCallback? onOpenApp;

  @override
  State<TasteCardScreen> createState() => _TasteCardScreenState();
}

class _TasteCardScreenState extends State<TasteCardScreen> {
  final ScrollController _scrollController = ScrollController();
  // The reason sections start folded under 조금 더 자세히 알아볼까요.
  var _expanded = false;

  @override
  void didUpdateWidget(covariant TasteCardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final snapshotChanged =
        oldWidget.viewData.snapshotRef != widget.viewData.snapshotRef;
    if (snapshotChanged) {
      _expanded = false;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleCard() {
    setState(() => _expanded = !_expanded);
    if (!_expanded && _scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: AppDurations.standard,
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// 술결 한입 → 전환 문구 → 왜 잘 맞았을까요 → 왜 부담이었을까요 → 저장.
  /// A reason section with nothing to say is left out, heading and all.
  List<Widget> _buildSlivers(TasteCardSnapshotViewData viewData) {
    final sections =
        <
          ({
            String key,
            String label,
            List<TasteCardParagraphViewData> paragraphs,
          })
        >[
          if (viewData.positive.isNotEmpty)
            (
              key: 'positive',
              label: '내 입맛에 잘 맞았던 이유',
              paragraphs: viewData.positive,
            ),
          if (viewData.burden.isNotEmpty)
            (
              key: 'burden',
              label: '조금 아쉽게 느껴졌던 이유',
              paragraphs: viewData.burden,
            ),
          if (viewData.balanced.isNotEmpty)
            (
              key: 'balanced',
              label: '편안하게 다가왔던 이유',
              paragraphs: viewData.balanced,
            ),
        ];
    return <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: 22)),
      SliverToBoxAdapter(
        child: _BiteSection(
          bite: viewData.bite,
          product: viewData.product,
          recordedAt: viewData.recordedAt,
        ),
      ),
      if (sections.isNotEmpty)
        SliverToBoxAdapter(
          child: _DetailBridge(expanded: _expanded, onToggle: _toggleCard),
        ),
      if (_expanded && sections.isNotEmpty) ...<Widget>[
        for (final (index, section) in sections.indexed)
          SliverToBoxAdapter(
            child: _ReasonSection(
              sectionKey: section.key,
              number: '0${index + 1}',
              label: section.label,
              paragraphs: section.paragraphs,
            ),
          ),
        // The 저장 button stands clear of the last reason box.
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ] else
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      if ((widget.onOpenApp, widget.onSave) case (null, final onSave?))
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _CardActions(onSave: onSave),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 34)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final viewData = widget.viewData;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _TasteCardColors.canvas,
        image: DecorationImage(
          image: AssetImage(
            'assets/images/paper/next_drink_quote_card_background.png',
          ),
          fit: BoxFit.fitWidth,
          repeat: ImageRepeat.repeatY,
          opacity: .24,
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: <Widget>[
              Expanded(
                child: CustomScrollView(
                  key: const ValueKey<String>('onboarding-page-scroll'),
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: _buildSlivers(viewData),
                ),
              ),
              if (widget.onOpenApp case final onOpenApp?)
                _OpenAppBar(onPressed: onOpenApp),
            ],
          ),
        ),
      ),
    );
  }
}
