import 'package:flutter/material.dart';

import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_term_tooltip.dart';
import '../../../widgets/paper_box.dart';
import '../../taste_card/presentation/widgets/taste_card_guide_body.dart';
import '../../taste_card/presentation/widgets/taste_card_guide_parts.dart';
import '../../taste_card/data/taste_card_snapshot_view_data.dart';

part 'result/taste_card_actions.dart';
part 'result/taste_card_bite_section.dart';
part 'result/taste_card_common.dart';
part 'result/taste_card_reason_section.dart';

const _useTasteCardDesignFixture = bool.fromEnvironment(
  'SOOL_TASTE_CARD_DESIGN_FIXTURE',
);

enum OnboardingResultLoadState { loading, retryable, failure }

class OnboardingResultStatusScreen extends StatelessWidget {
  const OnboardingResultStatusScreen({
    required this.state,
    this.onRetry,
    this.savedCard = false,
    super.key,
  });

  final OnboardingResultLoadState state;
  final VoidCallback? onRetry;

  /// Whether a saved card is being opened rather than a new one made.
  final bool savedCard;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (state) {
      OnboardingResultLoadState.loading when savedCard => (
        '술결카드를 불러오고 있어요',
        '잠시만 기다려 주세요.',
      ),
      _ when savedCard => ('술결카드를 불러오지 못했어요', '잠시 후 다시 시도해주세요.'),
      OnboardingResultLoadState.loading => (
        '술결을 정리하고 있어요',
        '방금 남긴 느낌에서 다음 선택에 도움이 될 기준을 찾고 있어요.',
      ),
      OnboardingResultLoadState.retryable => (
        '잠시 연결이 원활하지 않아요',
        '남긴 답변은 그대로 보관하고 있어요. 같은 내용으로 다시 시도할 수 있어요.',
      ),
      OnboardingResultLoadState.failure => (
        '술결을 완성하지 못했어요',
        '입력한 내용은 유지했어요. 잠시 후 다시 시도해주세요.',
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
                if (state == OnboardingResultLoadState.loading)
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
                if (state != OnboardingResultLoadState.loading) ...<Widget>[
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

class OnboardingResultScreen extends StatefulWidget {
  const OnboardingResultScreen({
    this.onSave,
    this.viewData,
    this.isSaved = false,
    this.onOpenApp,
    super.key,
  });

  /// The 저장 button's action; null leaves the button out, as on a saved
  /// card opened again.
  final VoidCallback? onSave;

  /// The server card; saved results and design fixtures pass it in.
  final TasteCardSnapshotViewData? viewData;
  final bool isSaved;

  /// On the web the card ends the onboarding: instead of the save button a
  /// bar fixed at the bottom sends the visitor to the app.
  final VoidCallback? onOpenApp;

  @override
  State<OnboardingResultScreen> createState() => _OnboardingResultScreenState();
}

class _OnboardingResultScreenState extends State<OnboardingResultScreen> {
  final ScrollController _scrollController = ScrollController();
  // The reason sections start folded under 조금 더 자세히 알아볼까요.
  var _expanded = false;

  TasteCardSnapshotViewData get _viewData {
    if (widget.viewData != null) {
      return widget.viewData!;
    }
    if (_useTasteCardDesignFixture) {
      return TasteCardSnapshotViewData.designFixture;
    }
    throw StateError('서버 술결카드 viewData가 필요합니다.');
  }

  @override
  void didUpdateWidget(covariant OnboardingResultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final snapshotChanged =
        oldWidget.viewData?.snapshotRef != widget.viewData?.snapshotRef;
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
        duration: const Duration(milliseconds: 280),
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
              label: '왜 잘 맞았을까요?',
              paragraphs: viewData.positive,
            ),
          if (viewData.burden.isNotEmpty)
            (key: 'burden', label: '왜 부담이었을까요?', paragraphs: viewData.burden),
          if (viewData.balanced.isNotEmpty)
            (
              key: 'balanced',
              label: '왜 편안했을까요?',
              paragraphs: viewData.balanced,
            ),
        ];
    return <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: 22)),
      SliverToBoxAdapter(
        child: _BiteSection(
          bite: viewData.bite,
          categoryLabel: viewData.product.categoryLabel,
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
            child: _CardActions(onSave: onSave, isSaved: widget.isSaved),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 34)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final viewData = _viewData;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _TasteCardColors.canvas,
        image: DecorationImage(
          image: AssetImage(
            'assets/component_assets/next_drink_quote_card_background.png',
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
