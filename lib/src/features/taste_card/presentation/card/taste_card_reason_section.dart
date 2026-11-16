part of '../taste_card_screen.dart';

// 왜 잘 맞았을까요 / 왜 부담이었을까요 / 왜 편안했을까요: 별명과 태그 아래, 같은 종이에
// 구역마다 선 하나를 긋고 들어갑니다. 답변 하나에 문단 하나씩 얇은 선으로 나뉩니다.

/// One reason section of the card: its key, heading and paragraphs.
typedef _Reasons = ({
  String key,
  String label,
  List<TasteCardParagraphViewData> paragraphs,
});

class _ReasonSection extends StatelessWidget {
  const _ReasonSection({
    required this.sectionKey,
    required this.number,
    required this.label,
    required this.paragraphs,
  });

  final String sectionKey;
  final String number;
  final String label;
  final List<TasteCardParagraphViewData> paragraphs;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey<String>('taste-card-$sectionKey'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 22),
          child: Divider(height: 1, color: _TasteCardColors.ticketLine),
        ),
        _NumberedSectionLabel(number: number, label: label),
        const SizedBox(height: 18),
        for (var index = 0; index < paragraphs.length; index++) ...<Widget>[
          _Paragraph(paragraph: paragraphs[index]),
          if (index != paragraphs.length - 1) const _ParagraphRule(),
        ],
      ],
    );
  }
}

/// The thin line between two paragraphs on the same sheet.
class _ParagraphRule extends StatelessWidget {
  const _ParagraphRule();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Divider(
        height: 1,
        thickness: 1,
        color: _TasteCardColors.ticketLine,
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.paragraph});

  final TasteCardParagraphViewData paragraph;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KeptText(paragraph.answer, style: _TasteCardText.cardTitle),
        const SizedBox(height: 6),
        _EmphasizedText(
          paragraph.text,
          style: _TasteCardText.cardBody,
          terms: paragraph.terms,
        ),
      ],
    );
  }
}
