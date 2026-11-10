import '../../../../design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../design/app_typography.dart';
import '../../../../widgets/paper_box.dart';
import '../../data/taste_card_snapshot_view_data.dart';

/// The pieces of the 다음 술 가이드 that the card and the home carousel both
/// draw: the pick ticket (flag, place, keyword). The gauge is the app's
/// shared LevelGauge.
abstract final class TasteCardGuideColors {
  /// The pick tickets: a shade deeper than the paper, with a tan edge.
  static const ticket = Color(0xFFF1E9DA);
  static const ticketLine = Color(0xFFD9CBB3);

  /// The card's deep wine: the guide title and the kept-direction chips.
  static const wineDeep = Color(0xFF53131A);
}

/// [🇺🇸 미국 워싱턴 | 그르나슈·가르나차]: the flag and place, then the word to
/// look for, on a ticket a shade deeper than the paper.
///
/// The flags are flag-icons (MIT, lipis), one file per country the region
/// tree has a root for; a country without a file shows no flag.
class TasteCardPickTicket extends StatelessWidget {
  const TasteCardPickTicket({required this.pick, super.key});

  final TasteCardGuidePickViewData pick;

  @override
  Widget build(BuildContext context) {
    final country = pick.country;
    final flag = country != null && tasteCardFlagCodes.contains(country)
        ? 'assets/icons/flags/$country.svg'
        : null;
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
          if (flag != null) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(2.5),
              child: SvgPicture.asset(flag, width: 18, height: 13.5),
            ),
            const SizedBox(width: 7),
          ],
          if (place != null) ...<Widget>[
            Text(
              place,
              style: const AppTextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: PaperInk.grey,
              ),
            ),
            Container(
              width: 1,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: TasteCardGuideColors.ticketLine,
            ),
          ],
          Flexible(
            child: Text(
              pick.keyword,
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

/// The countries with a flag file under taste_card/flags: the region roots.
const tasteCardFlagCodes = <String>{
  'am', 'ar', 'at', 'au', 'az', 'be', 'bg', 'br', 'ca', 'ch', 'cl', 'cn', //
  'cz', 'de', 'dk', 'eg', 'es', 'fi', 'fr', 'gb', 'ge', 'gr', 'hr', 'hu', //
  'id', 'ie', 'il', 'in', 'it', 'jo', 'jp', 'kr', 'lb', 'ma', 'md', 'mm', //
  'mx', 'nl', 'np', 'nz', 'ph', 'pt', 'ro', 'rs', 'se', 'si', 'sk', 'th', //
  'tr', 'tw', 'ua', 'us', 'uy', 'za',
};
