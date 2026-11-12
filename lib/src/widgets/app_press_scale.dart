import 'package:flutter/widgets.dart';

import '../design/app_tokens.dart';

/// Shrinks a card or a chip a little while it is pressed, so it gives under
/// the finger. The control inside reports its own pressed state through
/// `onPressedChanged` (an `InkWell.onHighlightChanged`), so a press that
/// turns into a scroll lets go as the highlight does.
class AppPressScale extends StatefulWidget {
  const AppPressScale({required this.builder, super.key});

  static const pressedScale = 0.97;

  final Widget Function(
    BuildContext context,
    ValueChanged<bool> onPressedChanged,
  )
  builder;

  @override
  State<AppPressScale> createState() => _AppPressScaleState();
}

class _AppPressScaleState extends State<AppPressScale> {
  bool _pressed = false;

  void _onPressedChanged(bool pressed) {
    if (mounted && pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: _pressed ? AppPressScale.pressedScale : 1,
    duration: AppDurations.fast,
    curve: Curves.easeOut,
    child: widget.builder(context, _onPressedChanged),
  );
}
