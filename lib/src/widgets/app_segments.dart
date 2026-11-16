import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';

/// A few choices as one control, one of them always chosen: a light track,
/// the chosen side a white pill with burgundy text and a soft shadow.
class AppSegments<T> extends StatelessWidget {
  const AppSegments({
    required this.options,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.segmentKey,
    super.key,
  });

  final List<T> options;
  final T selected;
  final String Function(T option) label;
  final ValueChanged<T> onChanged;

  /// The key of an option's side of the control.
  final Key Function(T option)? segmentKey;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.xs),
    decoration: BoxDecoration(
      color: AppColors.segmentTrack,
      borderRadius: BorderRadius.circular(AppRadii.chip),
    ),
    child: Row(
      children: <Widget>[
        for (final option in options)
          Expanded(
            child: Semantics(
              button: true,
              selected: option == selected,
              child: GestureDetector(
                key: segmentKey?.call(option),
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(option),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: option == selected
                        ? AppColors.surfacePrimary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                    boxShadow: option == selected
                        ? const <BoxShadow>[
                            BoxShadow(
                              color: AppColors.segmentSelectedShadow,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    label(option),
                    style: AppTextStyles.body.copyWith(
                      fontWeight: option == selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: option == selected
                          ? AppColors.actionPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
