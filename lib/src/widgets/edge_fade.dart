import 'package:flutter/material.dart';

/// Fades [child] out toward its edges so a photo melts into the page around
/// it instead of ending on a hard edge. Each value is the share of the height
/// ([top], [bottom]) or width ([sides]) the fade takes; the bottom is the
/// usual one.
class EdgeFade extends StatelessWidget {
  const EdgeFade({
    required this.child,
    this.bottom = .32,
    this.top = 0,
    this.sides = 0,
    super.key,
  });

  final Widget child;
  final double bottom;
  final double top;
  final double sides;

  static Shader _fade(
    Rect bounds,
    Axis axis,
    double start,
    double end,
  ) => LinearGradient(
    begin: axis == Axis.vertical ? Alignment.topCenter : Alignment.centerLeft,
    end: axis == Axis.vertical ? Alignment.bottomCenter : Alignment.centerRight,
    colors: const <Color>[
      Colors.transparent,
      Colors.black,
      Colors.black,
      Colors.transparent,
    ],
    stops: <double>[0, start, 1 - end, 1],
  ).createShader(bounds);

  @override
  Widget build(BuildContext context) {
    Widget faded = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => _fade(bounds, Axis.vertical, top, bottom),
      child: child,
    );
    if (sides > 0) {
      faded = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) =>
            _fade(bounds, Axis.horizontal, sides, sides),
        child: faded,
      );
    }
    return faded;
  }
}
