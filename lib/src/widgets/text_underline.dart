import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A solid line drawn just under the letters of its one-line [child], clear
/// of them. A font's own underline runs through the feet of Hangul, so a
/// word the reader can open is marked with this instead.
class TextUnderline extends SingleChildRenderObjectWidget {
  const TextUnderline({
    required this.color,
    required this.fontSize,
    required super.child,
    super.key,
  });

  final Color color;

  /// The child's font size as drawn; the line's gap and weight follow it.
  final double fontSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderTextUnderline(color, fontSize);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTextUnderline renderObject,
  ) => renderObject
    ..color = color
    ..fontSize = fontSize;
}

/// Paints [TextUnderline]'s line at its child's baseline.
class RenderTextUnderline extends RenderProxyBox {
  RenderTextUnderline(this._color, this._fontSize);

  /// Baseline to the line's top, and the line's weight, per font pixel.
  static const _gap = 0.24;
  static const _weight = 0.09;

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  double _fontSize;
  set fontSize(double value) {
    if (value == _fontSize) return;
    _fontSize = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final baseline = child?.getDistanceToBaseline(TextBaseline.alphabetic);
    if (baseline == null) return;
    final top = offset.dy + baseline + _fontSize * _gap;
    context.canvas.drawRect(
      Rect.fromLTWH(offset.dx, top, size.width, _fontSize * _weight),
      Paint()..color = _color,
    );
  }
}
