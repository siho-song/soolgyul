part of '../taste_card_screen.dart';

// 술결 한입 on one sheet: 기록한 술, 별명, 태그와 요약 한 줄, then the numbered
// sections: 잘 맞았던 이유, 아쉬웠던 이유, and last 다음 방향.

class _BiteSection extends StatelessWidget {
  const _BiteSection({
    required this.bite,
    required this.reasons,
    required this.product,
    required this.recordedAt,
    this.recordPrice,
  });

  final TasteCardBiteViewData bite;
  final List<_Reasons> reasons;
  final TasteCardProductViewData product;
  final DateTime? recordedAt;
  final RecordPriceEditor? recordPrice;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('taste-card-bite'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TasteSummaryCard(
          bite: bite,
          reasons: reasons,
          product: product,
          recordedAt: recordedAt,
          recordPrice: recordPrice,
        ),
      ],
    );
  }
}

/// The white box both halves of 술결 한입 sit in, as the home's boxes.
class _CardBox extends StatelessWidget {
  const _CardBox({required this.children, super.key});

  final List<Widget> children;

  /// How far a box stands in from the page's sides.
  static const inset = 18.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: inset),
      child: AppPanel(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

abstract final class _BiteText {
  static const title = AppTextStyle(
    fontSize: 22,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: _TasteCardColors.wineDeep,
  );
  static const body = AppTextStyle(
    fontSize: 15,
    height: 1.75,
    color: _TasteCardColors.inkSoft,
  );
}

class _TasteSummaryCard extends StatelessWidget {
  const _TasteSummaryCard({
    required this.bite,
    required this.reasons,
    required this.product,
    required this.recordedAt,
    this.recordPrice,
  });

  final TasteCardBiteViewData bite;
  final List<_Reasons> reasons;
  final TasteCardProductViewData product;
  final DateTime? recordedAt;
  final RecordPriceEditor? recordPrice;

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      children: <Widget>[
        _DrinkHeader(
          product: product,
          recordedAt: recordedAt,
          recordPrice: recordPrice,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Divider(height: 1, color: _TasteCardColors.ticketLine),
        ),
        KeptText(
          bite.nickname,
          key: const ValueKey<String>('taste-card-nickname'),
          style: _BiteText.title,
        ),
        if (bite.tags.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            key: const ValueKey<String>('taste-card-tags'),
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final tag in bite.tags) _SummaryTag(tag: tag),
            ],
          ),
        ],
        // The tags said as one line, then the reasons at length.
        const SizedBox(height: 14),
        _EmphasizedText(
          bite.summary,
          key: const ValueKey<String>('taste-card-summary'),
          style: _BiteText.body,
        ),
        for (final (index, section) in reasons.indexed)
          _ReasonSection(
            sectionKey: section.key,
            number: '0${index + 1}',
            label: section.label,
            paragraphs: section.paragraphs,
          ),
        // The last numbered section: 02 on a card with one reason section.
        if (bite.next case final next? when !next.isEmpty)
          _NextSection(number: '0${reasons.length + 1}', next: next),
      ],
    );
  }
}

/// One 핵심 요약 tag: #체리향, then the kind's icon (heart, arrow, prohibit,
/// check). The text is grey; the icon is red for liked and burden, else ink.
/// A tag the dictionary explains is underlined like a word in the prose and opens
/// the same balloon.
class _SummaryTag extends StatelessWidget {
  const _SummaryTag({required this.tag});

  final TasteCardTagViewData tag;

  @override
  Widget build(BuildContext context) {
    final chip = PaperChip(
      text: '#${tag.label}',
      icon: tasteCardTagIcons[tag.kind]!,
      iconColor: _tagIconColor(tag.kind),
      explained: tag.term != null,
    );
    final term = tag.term;
    if (term == null) return chip;
    return Builder(
      builder: (context) => GestureDetector(
        key: ValueKey<String>('taste-card-tag-term-${tag.label}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => showTermTooltip(
          context,
          title: term.label,
          kind: term.kind,
          text: term.description,
          headerAction: saveTermAction(context, term.key),
        ),
        child: chip,
      ),
    );
  }
}
