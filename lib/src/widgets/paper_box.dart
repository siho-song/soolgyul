import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../design/app_typography.dart';
import 'text_underline.dart';

/// The cream 한지 note every card box in the app sits on: the paper of the old
/// 취향 발자취 2월 note. The image carries its own torn edge on a transparent
/// ground, so a box takes no radius and no shadow. It is drawn nine-slice: the
/// torn rim keeps its thickness at any box size and only the flat middle
/// stretches.
class PaperBox extends StatelessWidget {
  const PaperBox({
    required this.child,
    this.padding = defaultPadding,
    this.margin = EdgeInsets.zero,
    super.key,
  });

  static const asset = 'assets/images/paper/paper_cream.webp';

  /// The room a box keeps around what is written on it.
  static const defaultPadding = EdgeInsets.fromLTRB(24, 26, 24, 28);

  static const decoration = BoxDecoration(
    image: DecorationImage(
      image: AssetImage(asset),
      // The torn rim lies within 40 px of each side of the 1400×560 image.
      // At scale 4 the image counts as 350×140 and the slice is in those
      // units, so the rim draws 10 logical px thick.
      centerSlice: Rect.fromLTRB(10, 10, 340, 130),
      scale: 4,
      filterQuality: FilterQuality.high,
    ),
  );

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: decoration,
      child: child,
    );
  }
}

/// The ink the paper boxes write with.
abstract final class PaperInk {
  static const ink = Color(0xFF1F2529);
  static const inkSoft = Color(0xFF34414A);

  /// Chip fill.
  static const chip = Color(0xFFF7F3EF);

  /// Chip text, captions and the gauge ends.
  static const grey = Color(0xFF7D7773);

  /// Ticket borders and the empty part of a gauge.
  static const line = Color(0xFFE9E2DC);

  /// The filled part of a gauge: 먹색, so only the headings carry wine.
  static const gauge = Color(0xFF4A4541);

  /// What was only noticed on a tasting note: a quiet grey-brown, between
  /// the wine of what was liked and the grey of what was a burden.
  static const noticed = Color(0xFF7A6455);
}

/// The pill a paper box writes its tags in: grey text, and after it one
/// small icon when the tag has a kind. An [explained] chip underlines its
/// text like a word in the card prose: it opens an explanation.
class PaperChip extends StatelessWidget {
  const PaperChip({
    required this.text,
    this.icon,
    this.iconColor = PaperInk.ink,
    this.background = PaperInk.chip,
    this.textColor = PaperInk.grey,
    this.explained = false,
    super.key,
  });

  final String text;

  /// An SVG asset path.
  final String? icon;
  final Color iconColor;
  final Color background;
  final Color textColor;
  final bool explained;

  @override
  Widget build(BuildContext context) {
    const fontSize = 13.0;
    const inset = 5.0;
    const iconSize = 14.0;
    final style = AppTextStyle(
      fontSize: fontSize,
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: textColor,
    );
    final label = Text(
      text,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Container(
      padding: EdgeInsets.fromLTRB(
        inset * 2,
        inset,
        icon == null ? inset * 2 : inset * 2 - 2,
        inset,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // A chip wider than its row ends in an ellipsis and stays one line.
          Flexible(
            child: explained
                ? TextUnderline(
                    color: textColor,
                    fontSize: MediaQuery.textScalerOf(context).scale(fontSize),
                    child: label,
                  )
                : label,
          ),
          if (icon case final icon?) ...<Widget>[
            SizedBox(width: inset),
            SvgPicture.asset(
              icon,
              width: iconSize,
              height: iconSize,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
          ],
        ],
      ),
    );
  }
}
