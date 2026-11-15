import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Widens the area in which a small control takes a tap, with nothing drawn
/// or laid out differently: a tap within [slop] of [child] that the child
/// does not take where it fell lands on the child's middle instead.
///
/// The wider area reaches only as far as the box this sits in (a Stack, a
/// Row, a Column): a parent does not pass on taps outside itself.
class AppTapSlop extends SingleChildRenderObjectWidget {
  const AppTapSlop({
    required this.slop,
    required Widget super.child,
    this.along,
    super.key,
  });

  /// How far beyond each of the child's edges a tap still counts.
  final EdgeInsets slop;

  /// For a row or a column of controls: the tap keeps its place along this
  /// axis, so it lands on the control it fell beside and on none when it
  /// fell beside a gap. `null` when [child] is one control.
  final Axis? along;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTapSlop(slop, along);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderTapSlop)
      ..slop = slop
      ..along = along;
  }
}

class _RenderTapSlop extends RenderProxyBox {
  _RenderTapSlop(this.slop, this.along);

  EdgeInsets slop;
  Axis? along;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final box = Offset.zero & size;
    if (size.isEmpty || !slop.inflateRect(box).contains(position)) {
      return false;
    }
    if (box.contains(position) && super.hitTest(result, position: position)) {
      return true;
    }
    final middle = box.center;
    return super.hitTest(
      result,
      position: switch (along) {
        null => middle,
        Axis.horizontal => Offset(position.dx, middle.dy),
        Axis.vertical => Offset(middle.dx, position.dy),
      },
    );
  }
}
