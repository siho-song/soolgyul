import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/app_layout.dart';
import '../design/app_tokens.dart';

/// Opens a short form with one field to type in, as a card resting just
/// over the keyboard. The card is shown where it will stay: at the height
/// the keyboard is known to take, or, on a phone whose keyboard the app
/// has never seen, once this one has come up. It does not ride up or down
/// with the keyboard, and the page under it stays as it was (see
/// `AppScreen`).
///
/// The form's field takes the cursor at once (`autofocus`).
Future<T?> showAppInputPopup<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  useSafeArea: false,
  builder: (context) => _OverKeyboard(child: builder(context)),
);

/// The tallest the keyboard has been, on this run or an earlier one.
double _keyboardHeight = 0;
ValueChanged<double>? _keepKeyboardHeight;

/// Given once as the app starts: the height kept from earlier runs, and
/// where a taller one is kept for the next.
void restoreKeyboardHeight(double kept, {required ValueChanged<double> keep}) {
  _keyboardHeight = math.max(_keyboardHeight, kept);
  _keepKeyboardHeight = keep;
}

/// Told by every page how much of the screen the keyboard covers, so a
/// popup opened later knows where the keyboard's top will be.
void noteKeyboardHeight(double inset) {
  if (inset <= _keyboardHeight) return;
  _keyboardHeight = inset;
  _keepKeyboardHeight?.call(inset);
}

/// The gap the card keeps from the screen's sides and from the keyboard.
const _gap = AppSpacing.sm;

class _OverKeyboard extends StatefulWidget {
  const _OverKeyboard({required this.child});

  final Widget child;

  @override
  State<_OverKeyboard> createState() => _OverKeyboardState();
}

class _OverKeyboardState extends State<_OverKeyboard>
    with TickerProviderStateMixin {
  /// Runs out when the keyboard has stopped moving, or never came: a phone
  /// may take most of a second to start raising it.
  late final _keyboardWait = AnimationController(
    vsync: this,
    duration: AppDurations.slow * 3,
  );
  late final _reveal = AnimationController(
    vsync: this,
    duration: AppDurations.fast,
  );
  double? _inset;

  @override
  void initState() {
    super.initState();
    if (_keyboardHeight > 0) {
      _reveal.value = 1;
      return;
    }
    _keyboardWait
      ..addStatusListener((status) {
        if (status.isCompleted) _reveal.forward();
      })
      ..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    noteKeyboardHeight(inset);
    // Still hidden and the keyboard moved: wait until it has been still.
    if (_inset != null && inset != _inset && _reveal.isDismissed) {
      _keyboardWait
        ..duration = AppDurations.fast
        ..forward(from: 0);
    }
    _inset = inset;
  }

  @override
  void dispose() {
    _keyboardWait.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = math.max(media.viewInsets.bottom, _keyboardHeight);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _gap,
        media.padding.top + _gap,
        _gap,
        (keyboard > 0 ? keyboard : media.padding.bottom) + _gap,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FadeTransition(
          opacity: _reveal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.regularPhoneWidth,
            ),
            child: Material(
              color: AppColors.surfacePrimary,
              clipBehavior: Clip.antiAlias,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(AppRadii.compactCard),
                ),
              ),
              child: SingleChildScrollView(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
