import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../../catalog/data/catalog_drink.dart';
import '../data/taste_fit_gateway.dart';
import '../data/taste_fit_verdict.dart';
import 'widgets/taste_fit_headline.dart';
import 'widgets/taste_fit_fact_chips.dart';
import 'widgets/taste_fit_level_card.dart';
import 'widgets/taste_fit_paper_card.dart';
import 'taste_fit_search_screen.dart';

/// One searched bottle: photo and names, the verdict and the levels on two
/// 한지 notes, and the button that starts a record with it. A bottle tapped
/// before its badge arrived asks [gateway] for its verdict and shows a
/// spinner in the verdict's place meanwhile.
class TasteFitDetailScreen extends StatefulWidget {
  const TasteFitDetailScreen({
    required this.selection,
    required this.onRecord,
    this.gateway,
    super.key,
  });

  final TasteFitSelection selection;
  final VoidCallback onRecord;
  final TasteFitGateway? gateway;

  static String? categoryLabelOf(DrinkCategory category) => switch (category) {
    DrinkCategory.redWine ||
    DrinkCategory.whiteWine ||
    DrinkCategory.sparklingWine => '와인',
    DrinkCategory.whisky => '위스키',
    DrinkCategory.sake => '사케',
    DrinkCategory.koreanTraditional => '전통주',
    DrinkCategory.other => null,
  };

  @override
  State<TasteFitDetailScreen> createState() => _TasteFitDetailScreenState();
}

class _TasteFitDetailScreenState extends State<TasteFitDetailScreen> {
  late TasteFitVerdict? _verdict = widget.selection.verdict;
  late bool _hasCards = widget.selection.hasCards;
  late bool _judging =
      !widget.selection.judged &&
      widget.selection.verdict == null &&
      widget.gateway != null;

  @override
  void initState() {
    super.initState();
    if (_judging) unawaited(_judge());
  }

  Future<void> _judge() async {
    TasteFitResponse? response;
    try {
      response = await widget.gateway!.judge(<String>[
        widget.selection.drink.id,
      ]);
    } on TasteFitGatewayException {
      // The bottle stays shown without a verdict.
    }
    if (!mounted) return;
    setState(() {
      _judging = false;
      if (response != null) {
        _verdict = response.verdictFor(widget.selection.drink.id);
        _hasCards = response.hasCards;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selection = widget.selection;
    final onRecord = widget.onRecord;
    final drink = selection.drink;
    final verdict = _verdict;
    final hasCards = _hasCards;
    final facts = <String>[
      ?TasteFitDetailScreen.categoryLabelOf(drink.category),
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
            const SizedBox(height: 14),
            Text(
              drink.displayName,
              textAlign: TextAlign.center,
              style: AppTextStyles.sectionTitle,
            ),
            if (hasCards && verdict != null) ...<Widget>[
              const SizedBox(height: 6),
              TasteFitHeadline(verdict: verdict),
            ],
            if (drink.nameEn case final nameEn?) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                nameEn,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall,
              ),
            ],
            if (facts.isNotEmpty) ...<Widget>[
              const SizedBox(height: 3),
              Text(
                facts,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall,
              ),
            ],
            if (drink.abvLabel case final abv?) ...<Widget>[
              const SizedBox(height: 6),
              _AbvStatement(abvLabel: abv),
            ],
            if (verdict != null && verdict.facts.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              TasteFitFactChips(facts: verdict.facts),
            ],
            const SizedBox(height: 14),
            if (_judging)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: CircularProgressIndicator(
                    key: ValueKey<String>('taste-fit-judging'),
                  ),
                ),
              )
            else if (!hasCards)
              const Text(
                tasteFitNoCardsHint,
                textAlign: TextAlign.center,
                style: AppTextStyles.modalBody,
              )
            else if (verdict != null)
              TasteFitPaperCard(verdict: verdict),
            if (levels.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
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
        color: AppColors.textSupporting,
      ),
    );
  }
}

/// The bottle in a 150×200 frame; without a photo the search icon keeps the
/// frame so the names sit at the same height.
class _Photo extends StatelessWidget {
  const _Photo({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const placeholder = Center(
      child: AppIcon(
        AppIconAsset.search,
        size: 32,
        color: AppColors.textTertiary,
        weight: AppIconWeight.strong,
      ),
    );
    return Container(
      width: 150,
      height: 200,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
