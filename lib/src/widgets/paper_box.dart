import 'package:flutter/material.dart';

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

  static const asset = 'assets/component_assets/taste_card/paper_cream.webp';

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
