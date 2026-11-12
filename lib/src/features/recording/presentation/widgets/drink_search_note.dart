import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/kept_text.dart';

/// A search's drinks under the line that says what they are: only like what
/// was typed, or bottles spelled like a drink the catalog does not carry.
/// Without a [note] the drinks stand alone.
class DrinkSearchNoted extends StatelessWidget {
  const DrinkSearchNoted({
    required this.note,
    required this.child,
    this.scrollable = false,
    super.key,
  });

  final String? note;
  final Widget child;

  /// Whether [child] scrolls by itself and takes the room that is left.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    if (note == null) return child;
    return Column(
      mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            0,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: KeptText(
            note,
            key: const ValueKey<String>('drink-search-note'),
            style: AppTextStyles.modalBody,
          ),
        ),
        if (scrollable) Expanded(child: child) else child,
      ],
    );
  }
}
