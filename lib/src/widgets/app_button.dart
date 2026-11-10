import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_icon.dart';

/// 버튼의 시각적 역할입니다. 크기와 독립적으로 조합합니다.
enum AppButtonVariant { primary, accent, secondary, tertiary, destructive }

/// 버튼의 공통 크기 단계입니다.
enum AppButtonSize { compact, regular, large, prominent }

/// 버튼이 부모의 가로 공간을 사용하는 방식입니다.
enum AppButtonWidthMode { expanded, intrinsic, fixed }

/// 술결 전역에서 사용하는 명령 버튼입니다.
///
/// 화면에서는 높이, 글자 크기, 패딩, 아이콘 크기, 간격과 모서리 반경을
/// 직접 지정하지 않고 [variant], [size], [widthMode]만 조합합니다.
class AppButton extends StatefulWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.regular,
    this.widthMode = AppButtonWidthMode.expanded,
    this.fixedWidth,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.isDisabled = false,
  }) : assert(
         widthMode != AppButtonWidthMode.fixed || fixedWidth != null,
         'fixed widthMode needs fixedWidth',
       ),
       assert(
         fixedWidth == null || fixedWidth >= AppSizes.minimumTapTarget,
         'fixedWidth must be at least the 44dp touch width',
       );

  final AppButtonVariant variant;
  final AppButtonSize size;
  final AppButtonWidthMode widthMode;

  /// [widthMode]가 [AppButtonWidthMode.fixed]일 때만 사용합니다.
  final double? fixedWidth;
  final String label;
  final AppIconAsset? leadingIcon;
  final AppIconAsset? trailingIcon;
  final bool isLoading;
  final bool isDisabled;
  final VoidCallback? onPressed;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  late final WidgetStatesController _statesController;

  @override
  void initState() {
    super.initState();
    _statesController = WidgetStatesController();
  }

  @override
  void dispose() {
    _statesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _ButtonMetrics.fromSize(widget.size);
    final textScaler = MediaQuery.textScalerOf(context);
    final scaledFontSize = textScaler.scale(metrics.fontSize);
    final accessibleVisualHeight = scaledFontSize * 1.2 + 16;
    final visualHeight = math.max(metrics.visualHeight, accessibleVisualHeight);
    final touchHeight = math.max(AppSizes.minimumTapTarget, visualHeight);
    final enabled =
        widget.onPressed != null && !widget.isDisabled && !widget.isLoading;
    final effectiveOnPressed = enabled ? widget.onPressed : null;

    final button = TextButton(
      statesController: _statesController,
      onPressed: effectiveOnPressed,
      style: _buttonStyle(
        metrics: metrics,
        touchHeight: touchHeight,
        variant: widget.variant,
      ),
      child: ValueListenableBuilder<Set<WidgetState>>(
        valueListenable: _statesController,
        builder: (context, states, _) {
          final colors = _ButtonColors.resolve(
            variant: widget.variant,
            states: states,
            enabled: enabled,
          );
          return _ButtonVisualSurface(
            label: widget.label,
            leadingIcon: widget.leadingIcon,
            trailingIcon: widget.trailingIcon,
            metrics: metrics,
            colors: colors,
            visualHeight: visualHeight,
            fillWidth: widget.widthMode != AppButtonWidthMode.intrinsic,
            isLoading: widget.isLoading,
          );
        },
      ),
    );

    final sizedButton = switch (widget.widthMode) {
      AppButtonWidthMode.expanded => SizedBox(
        width: double.infinity,
        child: button,
      ),
      AppButtonWidthMode.intrinsic => Align(
        alignment: Alignment.center,
        widthFactor: 1,
        heightFactor: 1,
        child: button,
      ),
      AppButtonWidthMode.fixed => SizedBox(
        width: widget.fixedWidth,
        child: button,
      ),
    };

    return Semantics(
      label: widget.isLoading ? '${widget.label}, 처리 중' : widget.label,
      button: true,
      enabled: enabled,
      onTap: effectiveOnPressed,
      excludeSemantics: true,
      child: sizedButton,
    );
  }
}

class _ButtonVisualSurface extends StatelessWidget {
  const _ButtonVisualSurface({
    required this.label,
    required this.leadingIcon,
    required this.trailingIcon,
    required this.metrics,
    required this.colors,
    required this.visualHeight,
    required this.fillWidth,
    required this.isLoading,
  });

  final String label;
  final AppIconAsset? leadingIcon;
  final AppIconAsset? trailingIcon;
  final _ButtonMetrics metrics;
  final _ButtonColors colors;
  final double visualHeight;
  final bool fillWidth;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label,
      maxLines: 1,
      softWrap: false,
      textAlign: TextAlign.center,
      style: metrics.labelStyle.copyWith(color: colors.foreground),
    );
    Widget icon(AppIconAsset asset) =>
        AppIcon(asset, size: metrics.iconSize, color: colors.foreground);
    final content = Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Opacity(
          opacity: isLoading ? 0 : 1,
          child: Row(
            mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (leadingIcon != null) ...<Widget>[
                icon(leadingIcon!),
                SizedBox(width: metrics.iconGap),
              ],
              if (fillWidth) Flexible(child: labelText) else labelText,
              if (trailingIcon != null) ...<Widget>[
                SizedBox(width: metrics.iconGap),
                icon(trailingIcon!),
              ],
            ],
          ),
        ),
        if (isLoading)
          SizedBox.square(
            dimension: metrics.iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(colors.foreground),
            ),
          ),
      ],
    );

    return AnimatedContainer(
      duration: AppDurations.fast,
      height: visualHeight,
      width: fillWidth ? double.infinity : null,
      padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(metrics.radius),
        border: colors.border == null
            ? null
            : Border.all(color: colors.border!, width: 1),
        boxShadow: colors.shadow,
      ),
      child: content,
    );
  }
}

ButtonStyle _buttonStyle({
  required _ButtonMetrics metrics,
  required double touchHeight,
  required AppButtonVariant variant,
}) {
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll<Size>(
      Size(AppSizes.minimumTapTarget, touchHeight),
    ),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.zero),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    splashFactory: NoSplash.splashFactory,
    animationDuration: AppDurations.fast,
    backgroundColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      return _ButtonColors.resolve(
        variant: variant,
        states: states,
        enabled: !states.contains(WidgetState.disabled),
      ).foreground;
    }),
    textStyle: WidgetStatePropertyAll<TextStyle>(metrics.labelStyle),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.radius),
      ),
    ),
  );
}

class _ButtonMetrics {
  const _ButtonMetrics({
    required this.visualHeight,
    required this.radius,
    required this.horizontalPadding,
    required this.fontSize,
    required this.iconSize,
    required this.iconGap,
  });

  final double visualHeight;
  final double radius;
  final double horizontalPadding;
  final double fontSize;
  final double iconSize;
  final double iconGap;

  TextStyle get labelStyle => AppTextStyles.buttonLabel.copyWith(
    fontSize: fontSize,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );

  factory _ButtonMetrics.fromSize(AppButtonSize size) {
    return switch (size) {
      AppButtonSize.compact => const _ButtonMetrics(
        visualHeight: 36,
        radius: 10,
        horizontalPadding: 14,
        fontSize: 13,
        iconSize: 14,
        iconGap: 6,
      ),
      AppButtonSize.regular => const _ButtonMetrics(
        visualHeight: 44,
        radius: 12,
        horizontalPadding: 18,
        fontSize: 15,
        iconSize: 18,
        iconGap: 8,
      ),
      AppButtonSize.large => const _ButtonMetrics(
        visualHeight: 50,
        radius: 14,
        horizontalPadding: 22,
        fontSize: 15,
        iconSize: 20,
        iconGap: 8,
      ),
      AppButtonSize.prominent => const _ButtonMetrics(
        visualHeight: 54,
        radius: 16,
        horizontalPadding: 24,
        fontSize: 16,
        iconSize: 20,
        iconGap: 8,
      ),
    };
  }
}

class _ButtonColors {
  const _ButtonColors({
    required this.background,
    required this.foreground,
    required this.border,
    required this.shadow,
  });

  final Color background;
  final Color foreground;
  final Color? border;
  final List<BoxShadow>? shadow;

  factory _ButtonColors.resolve({
    required AppButtonVariant variant,
    required Set<WidgetState> states,
    required bool enabled,
  }) {
    final pressed = states.contains(WidgetState.pressed);
    final hovered =
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused);

    final base = switch (variant) {
      AppButtonVariant.primary ||
      AppButtonVariant.accent => const _ButtonColors(
        background: AppColors.actionPrimary,
        foreground: AppColors.textOnPrimary,
        border: null,
        shadow: AppShadows.floatingControl,
      ),
      AppButtonVariant.secondary => const _ButtonColors(
        background: AppColors.surfaceCard,
        foreground: AppColors.actionPrimary,
        border: AppColors.actionPrimary,
        shadow: null,
      ),
      AppButtonVariant.tertiary => const _ButtonColors(
        background: Colors.transparent,
        foreground: AppColors.actionNeutral,
        border: null,
        shadow: null,
      ),
      AppButtonVariant.destructive => const _ButtonColors(
        background: AppColors.actionDestructive,
        foreground: AppColors.textOnPrimary,
        border: null,
        shadow: null,
      ),
    };

    if (!enabled) {
      return _ButtonColors(
        background: base.background.withValues(alpha: .42),
        foreground: base.foreground.withValues(alpha: .68),
        border: base.border?.withValues(alpha: .42),
        shadow: null,
      );
    }

    if (pressed) {
      return _ButtonColors(
        background: Color.alphaBlend(
          Colors.black.withValues(alpha: .12),
          base.background,
        ),
        foreground: base.foreground,
        border: base.border,
        shadow: null,
      );
    }

    if (hovered) {
      return _ButtonColors(
        background: Color.alphaBlend(
          Colors.black.withValues(alpha: .06),
          base.background,
        ),
        foreground: base.foreground,
        border: base.border,
        shadow: base.shadow,
      );
    }

    return base;
  }
}
