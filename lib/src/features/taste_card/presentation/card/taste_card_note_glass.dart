part of '../taste_card_screen.dart';

// The texture of a drink as small glasses drawn in ink: a cup of 탁주 by
// how far its cloud reaches, a wine glass by the legs on its wall.

/// One of the six drawings, by the name the server gives an option.
class _GlassPainter extends CustomPainter {
  const _GlassPainter(this.icon);

  final String icon;

  /// How much of the cup's drink the settled cloud takes.
  static const _clouds = <String, double>{
    'sediment_low': 0.2,
    'sediment_mid': 0.5,
    'sediment_high': 0.92,
  };

  /// How many legs run down the glass.
  static const _legs = <String, int>{
    'legs_light': 1,
    'legs_medium': 3,
    'legs_heavy': 5,
  };

  /// Whether [icon] names a drawing this app has.
  static bool draws(String? icon) =>
      _clouds.containsKey(icon) || _legs.containsKey(icon);

  /// The side of the square the drawings are laid out in.
  static const _side = 44.0;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = PaperInk.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..save()
      ..scale(size.shortestSide / _side);
    if (_clouds[icon] case final share?) {
      _paintCup(canvas, line, share);
    } else if (_legs[icon] case final count?) {
      _paintGlass(canvas, line, count);
    }
    canvas.restore();
  }

  /// A cup from the side, a little wider at its rim, holding a milky
  /// drink: clear above, and the cloud settled up to [share] of it.
  static void _paintCup(Canvas canvas, Paint line, double share) {
    const surface = 15.0;
    const floor = 38.0;
    final cup = Path()
      ..moveTo(8, 9)
      ..lineTo(11.5, 34)
      ..quadraticBezierTo(12, floor, 16, floor)
      ..lineTo(28, floor)
      ..quadraticBezierTo(32, floor, 32.5, 34)
      ..lineTo(36, 9);
    final settled = floor - (floor - surface) * share;
    final cloud = Path()
      ..moveTo(0, settled)
      ..quadraticBezierTo(14, settled - 1.8, 22, settled)
      ..quadraticBezierTo(30, settled + 1.8, _side, settled)
      ..lineTo(_side, floor)
      ..lineTo(0, floor)
      ..close();
    final specks = Paint()..color = PaperInk.ink.withValues(alpha: 0.35);
    canvas
      ..save()
      ..clipPath(Path.from(cup)..close())
      ..drawRect(
        const Rect.fromLTRB(0, surface, _side, floor),
        Paint()..color = PaperInk.ink.withValues(alpha: 0.06),
      )
      ..drawPath(
        cloud,
        Paint()
          ..color = TasteCardGuideColors.ticketLine.withValues(alpha: 0.85),
      );
    // A few grains in the cloud, wherever it reaches.
    for (final (across, up) in const <(double, double)>[
      (16, 0.25),
      (22, 0.6),
      (27, 0.35),
      (19, 0.8),
      (25.5, 0.85),
    ]) {
      canvas.drawCircle(
        Offset(across, floor - 1.5 - (floor - settled - 3) * up),
        0.7,
        specks,
      );
    }
    canvas
      ..drawLine(
        const Offset(0, surface),
        const Offset(_side, surface),
        Paint()
          ..color = PaperInk.ink.withValues(alpha: 0.55)
          ..strokeWidth = 0.9,
      )
      ..restore()
      ..drawPath(cup, line);
  }

  /// A wine glass from the side, tilted back as when its legs are watched:
  /// the wine level at the bottom of the bowl, and [count] legs down the
  /// wall above it, thicker and ending in drops the more there are.
  static void _paintGlass(Canvas canvas, Paint line, int count) {
    const middle = _side / 2;
    const tilt = -0.2;
    final bowl = Path()
      ..moveTo(11, 5)
      ..cubicTo(6, 20, 13, 31, middle, 31)
      ..cubicTo(31, 31, 38, 20, 33, 5);
    // Drawn in ink, not in a wine's red: the same glass stands for a white
    // wine and a whisky.
    final wine = PaperInk.ink;
    final heavy = count > 3;
    final leg = Paint()
      ..color = wine.withValues(alpha: 0.3 + 0.09 * count)
      ..style = PaintingStyle.stroke
      ..strokeWidth = heavy ? 1.9 : (count > 1 ? 1.0 : 0.9)
      ..strokeCap = StrokeCap.round;
    // Spread over the wall, the outer ones nearer its sides.
    final first = middle - (count - 1) * 2.25 * (heavy ? 1 : 1.3);
    final step = count == 1 ? 0.0 : (middle - first) * 2 / (count - 1);
    canvas
      ..save()
      ..translate(middle, middle)
      ..rotate(tilt)
      ..translate(-middle, -middle)
      ..save()
      ..clipPath(Path.from(bowl)..close());
    for (var index = 0; index < count; index += 1) {
      // A lone leg runs off the middle, on the wall tilted back.
      final across = count == 1 ? middle + 5 : first + step * index;
      final from = Offset(across, 8 + (index.isOdd ? 2.5 : 0));
      final to = Offset(
        across + (middle - across) * 0.12,
        19 + (index % 3) * 2,
      );
      canvas.drawLine(from, to, leg);
      if (heavy) {
        canvas.drawCircle(
          to,
          1.7,
          Paint()..color = wine.withValues(alpha: 0.75),
        );
      }
    }
    // The wine lies level whichever way the glass leans.
    canvas
      ..translate(middle, 25.5)
      ..rotate(-tilt)
      ..drawRect(
        const Rect.fromLTRB(-_side, 0, _side, _side),
        Paint()..color = wine.withValues(alpha: 0.45),
      )
      ..restore()
      ..drawPath(bowl, line)
      ..drawLine(const Offset(11, 5), const Offset(33, 5), line)
      ..drawLine(const Offset(middle, 31), const Offset(middle, 39.5), line)
      ..drawLine(const Offset(15, 39.5), const Offset(29, 39.5), line)
      ..restore();
  }

  @override
  bool shouldRepaint(_GlassPainter oldDelegate) => oldDelegate.icon != icon;
}
