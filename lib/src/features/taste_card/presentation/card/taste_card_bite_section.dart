part of '../taste_card_screen.dart';

// 술결 한입 in two boxes: the taste summary (기록한 술, 별명, 태그, 한 줄) and the next-drink
// guide (다음 술은 이렇게 골라보세요). Neither box carries a heading; the second
// is left out when the server wrote no guide. The 전환 문구 sits under them.

class _BiteSection extends StatelessWidget {
  const _BiteSection({
    required this.bite,
    required this.product,
    required this.recordedAt,
  });

  final TasteCardBiteViewData bite;
  final TasteCardProductViewData product;
  final DateTime? recordedAt;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('taste-card-bite'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TasteSummaryCard(bite: bite, product: product, recordedAt: recordedAt),
        if (bite.guide case final guide?) ...<Widget>[
          const SizedBox(height: 14),
          _SolutionCard(
            guide: guide,
            // 와인, 위스키, 사케, 한국 전통주: names the picks' section.
            categoryLabel: product.categoryLabel,
          ),
        ],
      ],
    );
  }
}

/// The 한지 note both halves of 술결 한입 sit on.
class _CardBox extends StatelessWidget {
  const _CardBox({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PaperBox(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
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
    required this.product,
    required this.recordedAt,
  });

  final TasteCardBiteViewData bite;
  final TasteCardProductViewData product;
  final DateTime? recordedAt;

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      children: <Widget>[
        _DrinkHeader(product: product, recordedAt: recordedAt),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Divider(height: 1, color: _TasteCardColors.ticketLine),
        ),
        Text(
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
        const SizedBox(height: 14),
        _EmphasizedText(
          bite.summary,
          key: const ValueKey<String>('taste-card-summary'),
          style: _BiteText.body,
        ),
      ],
    );
  }
}

/// One 핵심 요약 tag: #체리향, then the kind's icon (heart, arrow, prohibit,
/// check). The text is grey; the icon is red for liked and burden, else ink.
/// A tag the dictionary explains is dotted like a word in the prose and opens
/// the same balloon.
class _SummaryTag extends StatelessWidget {
  const _SummaryTag({required this.tag});

  final TasteCardTagViewData tag;

  @override
  Widget build(BuildContext context) {
    final red =
        tag.kind == TasteCardTagKind.liked ||
        tag.kind == TasteCardTagKind.burden;
    final chip = PaperChip(
      text: '#${tag.label}',
      icon: tasteCardTagIcons[tag.kind]!,
      iconColor: red ? _TasteCardColors.tagRed : _TasteCardColors.ink,
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
        ),
        child: chip,
      ),
    );
  }
}

/// The next-drink guide: its title and head sentence, then the shared body
/// (직접 chips, picks, marks, tip).
class _SolutionCard extends StatelessWidget {
  const _SolutionCard({required this.guide, required this.categoryLabel});

  final TasteCardGuideViewData guide;
  final String? categoryLabel;

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      key: const ValueKey<String>('taste-card-guide'),
      children: <Widget>[
        const Text('다음 술은 이렇게 골라보세요!', style: _BiteText.title),
        const SizedBox(height: 10),
        Text(guide.head, style: _BiteText.body),
        TasteCardGuideBody(guide: guide, categoryLabel: categoryLabel),
      ],
    );
  }
}

class _DetailBridge extends StatelessWidget {
  const _DetailBridge({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey<String>('taste-card-bridge'),
      padding: const EdgeInsets.fromLTRB(28, 30, 20, 4),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              '조금 더 자세히 알아볼까요?',
              style: AppTextStyle(
                fontSize: 18,
                height: 1.45,
                fontWeight: FontWeight.w700,
                color: _TasteCardColors.wineDeep,
              ),
            ),
          ),
          Semantics(
            button: true,
            expanded: expanded,
            label: expanded ? '상세 분석 접기' : '상세 분석 펼치기',
            child: TextButton.icon(
              key: const ValueKey<String>('taste-card-toggle'),
              onPressed: onToggle,
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: AppSizes.iconMd,
              ),
              label: Text(expanded ? '접기' : '펼치기'),
              style: TextButton.styleFrom(
                foregroundColor: _TasteCardColors.wineDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
