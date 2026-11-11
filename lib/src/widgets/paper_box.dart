import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../design/app_typography.dart';
import 'text_underline.dart';

/// The cream 한지 note every card box in the app sits on: the paper of the old
/// 취향 발자취 2월 note. The image carries its own torn edge, so a box takes no
/// radius and no shadow.
class PaperBox extends StatelessWidget {
  const PaperBox({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 26, 24, 28),
    this.margin = EdgeInsets.zero,
    super.key,
  });

  static const asset = 'assets/images/paper/paper_cream.webp';

  static const decoration = BoxDecoration(
    image: DecorationImage(
      image: AssetImage(asset),
      fit: BoxFit.fill,
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
}

/// The pill a paper box writes its tags in: grey text, and after it one
/// small icon when the tag has a kind. An [explained] chip underlines its
/// text like a word in the card prose: it opens an explanation. A [dense]
/// chip is a size smaller, for under a line of small text.
class PaperChip extends StatelessWidget {
  const PaperChip({
    required this.text,
    this.icon,
    this.iconColor = PaperInk.ink,
    this.background = PaperInk.chip,
    this.textColor = PaperInk.grey,
    this.explained = false,
    this.dense = false,
    super.key,
  });

  final String text;

  /// An SVG asset path.
  final String? icon;
  final Color iconColor;
  final Color background;
  final Color textColor;
  final bool explained;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fontSize = dense ? 12.0 : 13.0;
    final inset = dense ? 4.0 : 5.0;
    final iconSize = dense ? 13.0 : 14.0;
    final style = AppTextStyle(
      fontSize: fontSize,
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: textColor,
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
          if (explained)
            TextUnderline(
              color: textColor,
              fontSize: MediaQuery.textScalerOf(context).scale(fontSize),
              child: Text(text, style: style),
            )
          else
            Text(text, style: style),
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
