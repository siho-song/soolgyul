part of '../taste_card_screen.dart';

// 술결카드 여러 구역이 함께 쓰는 색, 글꼴, 작은 조각입니다.

abstract final class _TasteCardColors {
  static const canvas = Color(0xFFFCF9F6);
  static const wine = Color(0xFF66161D);
  static const wineDeep = TasteCardGuideColors.wineDeep;
  static const ink = PaperInk.ink;
  static const inkSoft = PaperInk.inkSoft;

  /// The heart and the prohibit sign on the 핵심 요약 tags.
  static const tagRed = Color(0xFFD63B3B);

  static const ticketLine = TasteCardGuideColors.ticketLine;
}

/// Card prose whose **marked** words (the engine's emphasis: the sensations
/// a paragraph is about, the verdict of its closing) are set bold in wine. A
/// marked word the dictionary explains ([terms]) also carries an
/// underline and opens its explanation in a balloon when touched; the text
/// itself never changes.
class _EmphasizedText extends StatelessWidget {
  const _EmphasizedText(
    this.text, {
    required this.style,
    this.terms = const <TasteCardTermViewData>[],
    super.key,
  });

  final String text;
  final TextStyle style;
  final List<TasteCardTermViewData> terms;

  @override
  Widget build(BuildContext context) {
    final strong = style.copyWith(
      fontWeight: FontWeight.w600,
      color: _TasteCardColors.wineDeep,
    );
    final parts = text.split('**');
    final spans = <InlineSpan>[];
    for (var i = 0; i < parts.length; i += 1) {
      if (parts[i].isEmpty) continue;
      final term = i.isOdd ? _termFor(parts[i]) : null;
      spans.add(
        term == null
            ? TextSpan(text: parts[i], style: i.isOdd ? strong : null)
            : WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: _TermWord(term: term, style: strong),
              ),
      );
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }

  TasteCardTermViewData? _termFor(String word) {
    for (final term in terms) {
      if (term.word == word) return term;
    }
    return null;
  }
}

/// One explained word inside the prose: drawn like its neighbours with a
/// solid line under it, and a touch opens the balloon right above it.
class _TermWord extends StatelessWidget {
  const _TermWord({required this.term, required this.style});

  final TasteCardTermViewData term;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey<String>('taste-card-term-${term.word}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showTermTooltip(
        context,
        title: term.label,
        kind: term.kind,
        text: term.description,
      ),
      child: TextUnderline(
        color: _TasteCardColors.wineDeep,
        fontSize: MediaQuery.textScalerOf(context).scale(style.fontSize!),
        child: Text(term.word, style: style),
      ),
    );
  }
}

abstract final class _TasteCardText {
  static const sectionLabel = AppTextStyle(
    fontSize: 15.5,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: _TasteCardColors.inkSoft,
  );

  static const headline = AppTextStyle(
    fontSize: 23,
    height: 1.58,
    fontWeight: FontWeight.w600,
    color: _TasteCardColors.ink,
  );

  static const body = AppTextStyle(
    fontSize: 14.5,
    height: 1.9,
    fontWeight: FontWeight.w400,
    color: _TasteCardColors.inkSoft,
  );

  static const cardTitle = AppTextStyle(
    fontSize: 16,
    height: 1.55,
    fontWeight: FontWeight.w600,
    color: _TasteCardColors.wineDeep,
  );

  static const cardBody = AppTextStyle(
    fontSize: 14,
    height: 1.85,
    fontWeight: FontWeight.w400,
    color: _TasteCardColors.inkSoft,
  );
}

class _NumberedSectionLabel extends StatelessWidget {
  const _NumberedSectionLabel({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              number,
              style: const AppTextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: _TasteCardColors.wineDeep,
              ),
            ),
            const SizedBox(height: 4),
            const SizedBox(
              width: 22,
              child: Divider(
                height: 1,
                thickness: 1,
                color: _TasteCardColors.wineDeep,
              ),
            ),
          ],
        ),
        const SizedBox(width: 22),
        Expanded(child: Text(label, style: _TasteCardText.sectionLabel)),
      ],
    );
  }
}
