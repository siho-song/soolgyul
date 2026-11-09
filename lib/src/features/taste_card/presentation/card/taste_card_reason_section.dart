part of '../taste_card_screen.dart';

// 왜 잘 맞았을까요 / 왜 부담이었을까요 / 왜 편안했을까요: 한 구역이 종이 한 장이고,
// 그 안에 답변 하나에 문단 하나씩 얇은 선으로 나뉘어 들어갑니다.

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
    return Padding(
      key: ValueKey<String>('taste-card-$sectionKey'),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: PaperBox.decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _NumberedSectionLabel(number: number, label: label),
            const SizedBox(height: 20),
            for (var index = 0; index < paragraphs.length; index++) ...<Widget>[
              _Paragraph(paragraph: paragraphs[index]),
              if (index != paragraphs.length - 1) const _ParagraphRule(),
            ],
          ],
        ),
      ),
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
        Text(paragraph.answer, style: _TasteCardText.cardTitle),
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
