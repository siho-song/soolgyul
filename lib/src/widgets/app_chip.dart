import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_icon.dart';
import 'app_press_scale.dart';

enum AppChipVariant { flat, soft, outline }

enum AppChipSize { compact, regular, filter }

/// [positive] and [negative] colour a selected chip as liked (light green)
/// or a burden (grey); unselected they look like [brand].
enum AppChipTone { brand, olive, warm, neutral, positive, negative }

class AppChip extends StatelessWidget {
  const AppChip({
    required this.label,
    super.key,
    this.variant = AppChipVariant.soft,
    this.size = AppChipSize.regular,
    this.tone = AppChipTone.brand,
    this.selected = false,
    this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.expand = false,
  });

  final String label;
  final AppChipVariant variant;
  final AppChipSize size;
  final AppChipTone tone;
  final bool selected;
  final VoidCallback? onPressed;
  final AppIconAsset? leadingIcon;
  final AppIconAsset? trailingIcon;

  /// Fill the width given, with the name centred, for chips laid out as
  /// equal columns.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final dimensions = _ChipDimensions.fromSize(size);
    final colors = _ChipColors.resolve(
      variant: variant,
      tone: tone,
      selected: selected,
    );
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.labelSmall.copyWith(
        fontSize: dimensions.fontSize,
        color: colors.foreground,
        fontWeight: dimensions.fontWeight,
      ),
    );
    Widget icon(AppIconAsset asset) =>
        AppIcon(asset, size: dimensions.iconSize, color: colors.foreground);

    final decoration = BoxDecoration(
      color: colors.background,
      borderRadius: BorderRadius.circular(dimensions.radius),
      border: colors.border == null ? null : Border.all(color: colors.border!),
    );
    final inner = Container(
      constraints: BoxConstraints(minHeight: dimensions.height),
      // An equal column is as wide as its row allows, so the name only needs
      // a small inset to keep clear of the rounded ends; three reaction
      // columns must still hold 적당했어요 on a 360px phone.
      padding: EdgeInsets.symmetric(
        horizontal: expand ? AppSpacing.xs : dimensions.horizontalPadding,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (leadingIcon != null) ...<Widget>[
            icon(leadingIcon!),
            SizedBox(width: dimensions.iconGap),
          ],
          if (expand) Flexible(child: text) else text,
          if (trailingIcon != null) ...<Widget>[
            SizedBox(width: dimensions.iconGap),
            icon(trailingIcon!),
          ],
        ],
      ),
    );

    if (onPressed == null) {
      return DecoratedBox(decoration: decoration, child: inner);
    }

    // The pressed look stays inside the chip, as on 탐색's hashtags; the
    // rest of the tap target around a small chip takes the tap without it.
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSizes.minimumTapTarget,
            minHeight: AppSizes.minimumTapTarget,
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: AppPressScale(
              builder: (context, onPressedChanged) => Material(
                type: MaterialType.transparency,
                borderRadius: BorderRadius.circular(dimensions.radius),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  onHighlightChanged: onPressedChanged,
                  child: Ink(decoration: decoration, child: inner),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipDimensions {
  const _ChipDimensions({
    required this.height,
    required this.horizontalPadding,
    required this.radius,
    required this.fontSize,
    required this.iconSize,
    required this.iconGap,
    required this.fontWeight,
  });

  final double height;
  final double horizontalPadding;
  final double radius;
  final double fontSize;
  final double iconSize;
  final double iconGap;
  final FontWeight fontWeight;

  factory _ChipDimensions.fromSize(AppChipSize size) {
    return switch (size) {
      AppChipSize.compact => const _ChipDimensions(
        height: 28,
        horizontalPadding: 10,
        radius: 14,
        fontSize: 12,
        iconSize: 14,
        iconGap: 6,
        fontWeight: FontWeight.w700,
      ),
      AppChipSize.regular => const _ChipDimensions(
        height: 34,
        horizontalPadding: 12,
        radius: 17,
        fontSize: 12,
        iconSize: 15,
        iconGap: 7,
        fontWeight: FontWeight.w800,
      ),
      AppChipSize.filter => const _ChipDimensions(
        height: 37,
        horizontalPadding: 14,
        radius: 19,
        fontSize: 13,
        iconSize: 16,
        iconGap: 6,
        fontWeight: FontWeight.w800,
      ),
    };
  }
}

class _ChipColors {
  const _ChipColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color? border;

  factory _ChipColors.resolve({
    required AppChipVariant variant,
    required AppChipTone tone,
    required bool selected,
  }) {
    if (selected && tone == AppChipTone.positive) {
      return const _ChipColors(
        background: Color(0xFFE4F0CC),
        foreground: Color(0xFF3F5222),
        border: Color(0xFFB7CF8A),
      );
    }
    if (selected && tone == AppChipTone.negative) {
      return const _ChipColors(
        background: Color(0xFFD3CFCB),
        foreground: Color(0xFF4A4642),
        border: Color(0xFFB9B4AF),
      );
    }
    final accent = switch (tone) {
      AppChipTone.brand ||
      AppChipTone.positive ||
      AppChipTone.negative => AppColors.actionPrimary,
      AppChipTone.olive => const Color(0xFF6F7540),
      AppChipTone.warm => const Color(0xFF6A4931),
      AppChipTone.neutral => AppColors.textSecondary,
    };
    final strongAccent = switch (tone) {
      AppChipTone.brand ||
      AppChipTone.positive ||
      AppChipTone.negative => AppColors.actionPrimaryStrong,
      AppChipTone.olive => const Color(0xFF4D5B2B),
      AppChipTone.warm => const Color(0xFF5D3D28),
      AppChipTone.neutral => AppColors.textPrimary,
    };

    if (selected) {
      return _ChipColors(
        background: accent,
        foreground: AppColors.textOnPrimary,
        border: accent,
      );
    }

    return switch (variant) {
      AppChipVariant.flat => _ChipColors(
        background: tone == AppChipTone.olive
            ? const Color(0xFFF2F2E7)
            : tone == AppChipTone.warm
            ? const Color(0xFFF5EEE7)
            : AppColors.surfaceSoft,
        foreground: strongAccent,
        border: null,
      ),
      AppChipVariant.soft => _ChipColors(
        background: AppColors.surfaceSoft,
        foreground: strongAccent,
        border: AppColors.borderSubtle,
      ),
      AppChipVariant.outline => _ChipColors(
        background: Colors.transparent,
        foreground: strongAccent,
        border: AppColors.borderSubtle,
      ),
    };
  }
}
