part of '../taste_card_screen.dart';

// How the paint chart of the 테이스팅 노트 is painted: a blot of watercolour
// for each colour and the arrow over the option picked. A dab follows from
// its option's key alone, so it is the same blot every time.

/// A number from an option's key, so its dab is always the same blot.
int _paintSeed(String key) {
  var seed = 7;
  for (final unit in key.codeUnits) {
    seed = (seed * 31 + unit) & 0x3FFFFFFF;
  }
  return seed;
}

/// Numbers from 0 to 1 that follow from a seed, the same on every phone
/// and in the browser.
class _Wobble {
  _Wobble(int seed) : _state = seed % (_modulus - 1) + 1;

  static const _modulus = 2147483647;
  int _state;

  double next() {
    _state = (_state * 16807) % _modulus;
    return _state / _modulus;
  }
}

/// A blot of watercolour on the paper: a ragged round edge where the wash
/// stopped, the paint pooled darker and uneven along it, and a centre left
/// lighter where it lies thin.
class _DabPainter extends CustomPainter {
  const _DabPainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  /// A closed curve around [center], its radius shrinking unevenly from
  /// [radius] by up to [ragged] of it.
  static Path _blot(
    Offset center,
    double radius,
    _Wobble wobble, {
    required double ragged,
  }) {
    const points = 14;
    const turn = 2 * 3.141592653589793 / points;
    final edge = <Offset>[
      for (var index = 0; index < points; index += 1)
        center +
            Offset.fromDirection(
              turn * (index + (wobble.next() - 0.5) * 0.5),
              radius * (1 - ragged * wobble.next()),
            ),
    ];
    // Rounded through the middle of each side, every point a pull.
    Offset between(int index) => (edge[index] + edge[(index + 1) % points]) / 2;
    final start = between(points - 1);
    final path = Path()..moveTo(start.dx, start.dy);
    for (var index = 0; index < points; index += 1) {
      final to = between(index);
      path.quadraticBezierTo(edge[index].dx, edge[index].dy, to.dx, to.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final wobble = _Wobble(seed);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final wash = _blot(center, radius, wobble, ragged: 0.14);
    final drift =
        Offset(wobble.next() - 0.5, wobble.next() - 0.5) * radius * 0.1;
    final body = _blot(center + drift, radius * 0.92, wobble, ragged: 0.1);

    // The first wash, thin to its ragged edge.
    canvas.drawPath(wash, Paint()..color = color.withValues(alpha: 0.42));
    // Where the paint pooled before it dried: the rim, uneven.
    canvas.drawPath(
      Path.combine(PathOperation.difference, wash, body),
      Paint()
        ..color = Color.lerp(color, PaperInk.ink, 0.3)!.withValues(alpha: 0.85),
    );
    canvas.drawPath(body, Paint()..color = color.withValues(alpha: 0.8));
    // The centre, a little off the middle, where the paper shows through.
    final thin = center + Offset(-radius * 0.18, -radius * 0.2);
    final reach = radius * 0.7;
    canvas
      ..save()
      ..clipPath(body)
      ..drawCircle(
        thin,
        reach,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              _TasteCardColors.canvas.withValues(alpha: 0.3),
              _TasteCardColors.canvas.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: thin, radius: reach)),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_DabPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}

/// The arrow of a paint chart, drawn by hand in ink: a shaft that leans a
/// little, down to a point just over the dab.
class _PickArrowPainter extends CustomPainter {
  const _PickArrowPainter(this.seed);

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final wobble = _Wobble(seed);
    final lean = (wobble.next() - 0.5) * 3;
    final tip = Offset(size.width / 2, size.height - 2);
    final top = Offset(tip.dx + lean, 1);
    final bend = Offset(tip.dx - lean, size.height / 2);
    const barb = 4.0;
    final path = Path()
      ..moveTo(top.dx, top.dy)
      ..quadraticBezierTo(bend.dx, bend.dy, tip.dx, tip.dy)
      ..moveTo(tip.dx - barb, tip.dy - barb + wobble.next())
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(tip.dx + barb - wobble.next(), tip.dy - barb);
    canvas.drawPath(
      path,
      Paint()
        ..color = _TasteCardColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PickArrowPainter oldDelegate) => oldDelegate.seed != seed;
}
