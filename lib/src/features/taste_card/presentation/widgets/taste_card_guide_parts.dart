import 'package:flutter/material.dart';

import '../../../../design/app_typography.dart';
import '../../../../widgets/paper_box.dart';
import '../../data/taste_card_snapshot_view_data.dart';

/// Colours, the caption style and the tag icons the card's boxes share.
/// They carry the name of the 다음 술 가이드 they were first drawn for; the
/// card no longer draws that guide.
abstract final class TasteCardGuideColors {
  /// A shade deeper than the paper, with a tan edge.
  static const ticket = Color(0xFFF1E9DA);
  static const ticketLine = Color(0xFFD9CBB3);

  /// The card's deep wine.
  static const wineDeep = Color(0xFF53131A);
}

/// The grey caption under a line of the card.
abstract final class TasteCardGuideText {
  static const caption = AppTextStyle(
    fontSize: 14,
    height: 1.5,
    color: PaperInk.grey,
  );
}

/// The small icon after a 핵심 요약 tag, by its kind.
const tasteCardTagIcons = <TasteCardTagKind, String>{
  TasteCardTagKind.liked: 'assets/icons/guide_tags/heart.svg',
  TasteCardTagKind.less: 'assets/icons/guide_tags/arrow_down.svg',
  TasteCardTagKind.burden: 'assets/icons/guide_tags/prohibit.svg',
  TasteCardTagKind.more: 'assets/icons/guide_tags/arrow_up.svg',
  TasteCardTagKind.fine: 'assets/icons/guide_tags/check.svg',
};
