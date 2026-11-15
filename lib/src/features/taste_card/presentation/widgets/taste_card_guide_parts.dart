import '../../../../design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../design/app_typography.dart';
import '../../../../widgets/app_term_tooltip.dart';
import '../../../../widgets/paper_box.dart';
import '../../../../widgets/text_underline.dart';
import '../../../glossary/presentation/widgets/save_term_button.dart';
import '../../data/taste_card_snapshot_view_data.dart';

/// The pieces of the 다음 술 가이드 that the card and the home carousel both
/// draw: the pick ticket (flag, place, label words) and a chip's words. The
/// gauge is the app's shared LevelGauge.
abstract final class TasteCardGuideColors {
  /// The pick tickets: a shade deeper than the paper, with a tan edge.
  static const ticket = Color(0xFFF1E9DA);
  static const ticketLine = Color(0xFFD9CBB3);

  /// The card's deep wine: the guide title.
  static const wineDeep = Color(0xFF53131A);
}

/// Opens [term]'s explanation against [anchor], the touched word, with the
/// button that saves it to 나의 용어 사전.
void showGuideTerm(BuildContext anchor, TasteCardTermViewData term) =>
    showTermTooltip(
      anchor,
      title: term.label,
      kind: term.kind,
      text: term.description,
      headerAction: saveTermAction(anchor, term.key),
    );

/// A chip's label words in one line: Merlot(메를로), or dry · trocken. A word
/// the dictionary explains is underlined and opens its own explanation,
/// unless [explain] is off. [trail] is written after them, as it is.
class TasteCardPickWords extends StatelessWidget {
  const TasteCardPickWords({
    required this.words,
    required this.style,
    this.trail,
    this.explain = true,
    super.key,
  });

  final List<TasteCardGuideWordViewData> words;
  final TextStyle style;
  final String? trail;
  final bool explain;

  static const _separator = ' · ';

  @override
  Widget build(BuildContext context) {
    final trail = this.trail;
    if (!explain || words.every((word) => word.term == null)) {
      final line = words.map((word) => word.text).join(_separator);
      return Text('$line${trail ?? ''}', style: style);
    }
    // Each word is its own piece, so only the letters an explanation is
    // about are underlined and open it; the dot stays with the word before.
    return Wrap(
      children: <Widget>[
        for (final (index, word) in words.indexed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(child: _word(context, word)),
              if (index < words.length - 1)
                Text(_separator, style: style)
              else if (trail != null)
                Text(trail, style: style),
            ],
          ),
      ],
    );
  }

  Widget _word(BuildContext context, TasteCardGuideWordViewData word) {
    final text = Text(word.text, style: style);
    final term = word.term;
    if (term == null) return text;
    return Builder(
      builder: (wordContext) => GestureDetector(
        key: ValueKey<String>('taste-card-pick-term-${word.text}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => showGuideTerm(wordContext, term),
        child: TextUnderline(
          color: style.color ?? PaperInk.ink,
          fontSize: MediaQuery.textScalerOf(context).scale(style.fontSize!),
          child: text,
        ),
      ),
    );
  }
}

/// [🇺🇸 미국 워싱턴 | Grenache(그르나슈)]: the flag and place, then the words
/// to look for, on a ticket a shade deeper than the paper.
///
/// The flags are flag-icons (MIT, lipis), one file per country the region
/// tree has a root for; a country without a file shows no flag.
class TasteCardPickTicket extends StatelessWidget {
  const TasteCardPickTicket({
    required this.pick,
    this.explain = true,
    super.key,
  });

  final TasteCardGuidePickViewData pick;
  final bool explain;

  @override
  Widget build(BuildContext context) {
    final place = pick.place;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: TasteCardGuideColors.ticket,
        border: Border.all(color: TasteCardGuideColors.ticketLine),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (place != null) ...<Widget>[
            TasteCardPickPlace(country: pick.country, place: place),
            Container(
              width: 1,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: TasteCardGuideColors.ticketLine,
            ),
          ],
          Flexible(
            child: TasteCardPickWords(
              words: pick.shownWords,
              trail: pick.trail,
              explain: explain,
              style: const AppTextStyle(
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: PaperInk.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 🇺🇸 미국 워싱턴: where a pick comes from, the flag first when there is a
/// file for the country.
class TasteCardPickPlace extends StatelessWidget {
  const TasteCardPickPlace({
    required this.country,
    required this.place,
    super.key,
  });

  final String? country;
  final String place;

  @override
  Widget build(BuildContext context) {
    final country = this.country;
    final flag = country != null && tasteCardFlagCodes.contains(country)
        ? 'assets/icons/flags/$country.svg'
        : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (flag != null) ...<Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(2.5),
            child: SvgPicture.asset(flag, width: 18, height: 13.5),
          ),
          const SizedBox(width: 7),
        ],
        Text(
          place,
          style: const AppTextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: PaperInk.grey,
          ),
        ),
      ],
    );
  }
}

/// The countries with a flag file under taste_card/flags: the region roots.
const tasteCardFlagCodes = <String>{
  'am', 'ar', 'at', 'au', 'az', 'be', 'bg', 'br', 'ca', 'ch', 'cl', 'cn', //
  'cz', 'de', 'dk', 'eg', 'es', 'fi', 'fr', 'gb', 'ge', 'gr', 'hr', 'hu', //
  'id', 'ie', 'il', 'in', 'it', 'jo', 'jp', 'kr', 'lb', 'ma', 'md', 'mm', //
  'mx', 'nl', 'np', 'nz', 'ph', 'pt', 'ro', 'rs', 'se', 'si', 'sk', 'th', //
  'tr', 'tw', 'ua', 'us', 'uy', 'za',
};
