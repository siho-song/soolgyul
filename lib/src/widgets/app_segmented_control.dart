import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_icon.dart';

enum AppSegmentedControlVariant { panel, pill }

class AppSegment<T> {
  const AppSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final AppIconAsset? icon;
}

class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    required this.segments,
    required this.selectedValue,
    required this.onSelected,
    super.key,
    this.variant = AppSegmentedControlVariant.panel,
  });

  final List<AppSegment<T>> segments;
  final T selectedValue;
  final ValueChanged<T> onSelected;
  final AppSegmentedControlVariant variant;

  @override
  Widget build(BuildContext context) {
    final isPill = variant == AppSegmentedControlVariant.pill;
    final row = Row(
      children: <Widget>[
        for (final segment in segments)
          Expanded(
            child: _SegmentButton<T>(
              segment: segment,
              selected: segment.value == selectedValue,
              onPressed: () => onSelected(segment.value),
              variant: variant,
            ),
          ),
      ],
    );

    if (!isPill) {
      return row;
    }

    return Container(
      height: AppSizes.minimumTapTarget + 2,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: AppColors.surfacePrimary.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(AppRadii.chip),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: row,
    );
  }
}

class _SegmentButton<T> extends StatelessWidget {
  const _SegmentButton({
    required this.segment,
    required this.selected,
    required this.onPressed,
    required this.variant,
  });

  final AppSegment<T> segment;
  final bool selected;
  final VoidCallback onPressed;
  final AppSegmentedControlVariant variant;

  @override
  Widget build(BuildContext context) {
    final isPill = variant == AppSegmentedControlVariant.pill;
    final foreground = selected
        ? AppColors.textOnPrimary
        : AppColors.actionPrimaryStrong;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.actionPrimary : Colors.transparent,
        borderRadius: BorderRadius.circular(isPill ? 18 : 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSizes.minimumTapTarget,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(isPill ? 18 : 12),
              boxShadow: selected && isPill
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x16800010),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (segment.icon != null) ...<Widget>[
                  AppIcon(
                    segment.icon!,
                    size: 18,
                    color: foreground,
                    weight: AppIconWeight.strong,
                  ),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(
                    segment.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle(
                      fontSize: isPill ? 13 : 11,
                      color: isPill && !selected
                          ? const Color(0xFF6A625E)
                          : foreground,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
