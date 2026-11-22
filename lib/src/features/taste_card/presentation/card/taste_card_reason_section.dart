part of '../taste_card_screen.dart';

// 왜 잘 맞았을까요 / 왜 부담이었을까요 / 왜 편안했을까요: 별명과 태그 아래, 같은 종이에
// 구역마다 선 하나를 긋고 들어갑니다. 답변 하나에 문단 하나씩 얇은 선으로 나뉩니다.
// 문단의 글은 이유 하나에 점 하나씩 띄워 그립니다.

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
        _SectionHead(number: number, label: label),
        for (var index = 0; index < paragraphs.length; index++) ...<Widget>[
          _Paragraph(paragraph: paragraphs[index]),
          if (index != paragraphs.length - 1) const _ParagraphRule(),
        ],
      ],
    );
  }
}

/// How a numbered section opens: a line across the sheet, then its number
/// and name.
class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 22),
          child: Divider(height: 1, color: _TasteCardColors.ticketLine),
        ),
        _NumberedSectionLabel(number: number, label: label),
        const SizedBox(height: 18),
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

  /// The mark the server opens each point of a section with.
  static const _point = '• ';

  @override
  Widget build(BuildContext context) {
    final lines = _lines(paragraph.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KeptText(paragraph.answer, style: _TasteCardText.cardTitle),
        const SizedBox(height: 6),
        for (final (index, line) in lines.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: AppSpacing.s10),
          if (line.startsWith(_point))
            _ReasonPoint(
              text: line.substring(_point.length),
              terms: paragraph.terms,
            )
          else
            _EmphasizedText(
              line,
              style: _TasteCardText.cardBody,
              terms: paragraph.terms,
            ),
        ],
      ],
    );
  }

  /// The text as its lines: a point a reason. A card written before the list
  /// form is one line without a mark, and is drawn as it was.
  static List<String> _lines(String text) => text
      .split(RegExp(r'\n+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

/// One reason of a section: a dot, and its sentence hanging beside it.
class _ReasonPoint extends StatelessWidget {
  const _ReasonPoint({required this.text, required this.terms});

  final String text;
  final List<TasteCardTermViewData> terms;

  @override
  Widget build(BuildContext context) {
    const style = _TasteCardText.cardBody;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 16,
          child: ExcludeSemantics(
            child: Text(
              '•',
              style: style.copyWith(color: _TasteCardColors.wineDeep),
            ),
          ),
        ),
        Expanded(
          child: _EmphasizedText(text, style: style, terms: terms),
        ),
      ],
    );
  }
}

/// 다음 방향: the last numbered section of the sheet. What to choose next, a
/// point a sentence; the names to look for are set bold, and an explained one
/// opens its balloon as a reason's words do.
class _NextSection extends StatelessWidget {
  const _NextSection({required this.number, required this.next});

  final String number;
  final TasteCardNextViewData next;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('taste-card-next'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionHead(number: number, label: '다음 방향'),
        for (final (index, line) in next.lines.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: AppSpacing.s10),
          _ReasonPoint(text: line.text, terms: line.terms),
        ],
      ],
    );
  }
}
