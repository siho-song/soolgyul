import '../../../widgets/drink_photo_placeholder.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../data/taste_fit_gateway.dart';
import '../data/taste_fit_verdict.dart';
import 'widgets/taste_fit_headline.dart';
import 'widgets/taste_fit_fact_chips.dart';
import 'widgets/taste_fit_level_card.dart';
import 'widgets/taste_fit_paper_card.dart';
import 'taste_fit_search_screen.dart';
import '../../../widgets/app_network_image.dart';
import '../../../widgets/app_state_view.dart';

/// One searched bottle: photo and names, the verdict and the levels on two
/// 한지 notes, and the button that starts a record with it. A bottle tapped
/// before its badge arrived asks [gateway] for its verdict and shows a
/// spinner in the verdict's place meanwhile; a verdict that did not come
/// says so there and can be asked for again.
class TasteFitDetailScreen extends StatefulWidget {
  const TasteFitDetailScreen({
    required this.selection,
    required this.onRecord,
    this.gateway,
    this.onJudged,
    this.revision = 0,
    super.key,
  });

  final TasteFitSelection selection;
  final VoidCallback onRecord;
  final TasteFitGateway? gateway;

  /// Called with the verdict this page asked for itself, once it came.
  final void Function(TasteFitVerdict? verdict, bool hasCards)? onJudged;

  /// Changes when a record was saved. The verdict is drawn from the
  /// reader's cards, so the page asks for it again.
  final int revision;

  @override
  State<TasteFitDetailScreen> createState() => _TasteFitDetailScreenState();
}

class _TasteFitDetailScreenState extends State<TasteFitDetailScreen> {
  late TasteFitVerdict? _verdict = widget.selection.verdict;
  late bool _hasCards = widget.selection.hasCards;

  /// Whether the fit call has answered for this bottle. Until it has,
  /// nothing is known of the reader's cards.
  late bool _judged = widget.selection.judged;
  bool _judging = false;
  bool _failed = false;

  /// Goes up with every fit call, so a late answer to an older one is
  /// dropped.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    if (!_judged && _verdict == null) _startJudging();
  }

  @override
  void didUpdateWidget(covariant TasteFitDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != oldWidget.revision) _startJudging();
  }

  /// Asks for the verdict. Called where a build follows.
  void _startJudging() {
    final gateway = widget.gateway;
    if (gateway == null) return;
    _judging = true;
    _failed = false;
    unawaited(_judge(gateway, ++_request));
  }

  Future<void> _judge(TasteFitGateway gateway, int request) async {
    TasteFitResponse? response;
    try {
      response = await gateway.judge(<String>[widget.selection.drink.id]);
    } on TasteFitGatewayException {
      // Said in the verdict's place, with the retry.
    }
    if (!mounted || request != _request) return;
    setState(() {
      _judging = false;
      if (response == null) {
        _failed = true;
      } else {
        _verdict = response.verdictFor(widget.selection.drink.id);
        _hasCards = response.hasCards;
        _judged = true;
      }
    });
    if (response != null) widget.onJudged?.call(_verdict, _hasCards);
  }

  @override
  Widget build(BuildContext context) {
    final selection = widget.selection;
    final onRecord = widget.onRecord;
    final drink = selection.drink;
    final verdict = _verdict;
    final hasCards = _hasCards;
    final facts = <String>[
      ?drink.category.type?.label,
      ?drink.styleLabel,
    ].join(' · ');
    final levels = verdict?.levels ?? const <String, int>{};
    return AppPageScrollView(
      topPadding: AppSpacing.md,
      bottomPadding: AppSpacing.xxxl,
      child: AppContentPadding(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(child: _Photo(url: drink.photoUrl)),
            const SizedBox(height: AppSpacing.s14),
            Text(
              drink.displayName,
              textAlign: TextAlign.center,
              style: AppTextStyles.sectionTitle,
            ),
            if (hasCards && verdict != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              TasteFitHeadline(verdict: verdict),
            ],
            if (drink.nameEn case final nameEn?) ...<Widget>[
              const SizedBox(height: AppSpacing.s6),
              Text(
                nameEn,
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),
            ],
            if (facts.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                facts,
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),
            ],
            if (drink.abvLabel case final abv?) ...<Widget>[
              const SizedBox(height: AppSpacing.s6),
              _AbvStatement(abvLabel: abv),
            ],
            if (verdict != null && verdict.facts.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              TasteFitFactChips(facts: verdict.facts),
            ],
            const SizedBox(height: AppSpacing.s14),
            // A verdict already shown stays while it is asked for again.
            if (hasCards && verdict != null)
              TasteFitPaperCard(verdict: verdict)
            else if (_judging)
              const AppLoadingView(
                key: ValueKey<String>('taste-fit-judging'),
                compact: true,
              )
            else if (_failed)
              AppCardError(
                key: const ValueKey<String>('taste-fit-judge-failed'),
                message: tasteFitJudgeFailedMessage,
                onRetry: () => setState(_startJudging),
              )
            // Only a reader the server said has no cards is asked for one.
            else if (_judged && !hasCards)
              const Text(
                tasteFitNoCardsHint,
                textAlign: TextAlign.center,
                style: AppTextStyles.modalBody,
              ),
            if (levels.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.s14),
              TasteFitLevelCard(levels: levels),
            ],
            const SizedBox(height: AppSpacing.xxl),
            AppButton(
              key: const ValueKey<String>('taste-fit-record-button'),
              label: '이 술 기록하기',
              size: AppButtonSize.prominent,
              onPressed: onRecord,
            ),
          ],
        ),
      ),
    );
  }
}

/// The strength the way a label prints it: "ALC. 40% VOL", small and spaced.
class _AbvStatement extends StatelessWidget {
  const _AbvStatement({required this.abvLabel});

  final String abvLabel;

  @override
  Widget build(BuildContext context) {
    return Text(
      'ALC. $abvLabel VOL',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.4,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// The bottle in a 150×200 frame; without a photo the placeholder drawing keeps
/// the frame so the names sit at the same height.
class _Photo extends StatelessWidget {
  const _Photo({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const placeholder = DrinkPhotoPlaceholder();
    return Container(
      width: 150,
      height: 200,
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: url == null
          ? placeholder
          : Image(
              image: networkImageProvider(url!),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
