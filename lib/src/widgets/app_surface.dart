import 'package:flutter/material.dart';

import '../design/app_tokens.dart';

enum AppSurfaceVariant {
  flat,

  /// 앱 전역에서 사용하는 기본 콘텐츠 카드입니다.
  ///
  /// 홈 카드와 동일한 배경색과 음영을 사용하며 별도 선 테두리는
  /// 그리지 않습니다.
  card,
  outlined,
  elevated,
  tinted,
}

class AppSurface extends StatelessWidget {
  const AppSurface({
    required this.child,
    super.key,
    this.variant = AppSurfaceVariant.flat,
    this.padding = EdgeInsets.zero,
    this.borderRadius = AppRadii.card,
    this.backgroundColor,
    this.height,
    this.width,
    this.borderColor,
    this.borderWidth = 1,
    this.boxShadow,
    this.backgroundImage,
    this.onPressed,
    this.semanticLabel,
  });

  final Widget child;
  final AppSurfaceVariant variant;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? backgroundColor;
  final double? height;
  final double? width;
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow>? boxShadow;
  final DecorationImage? backgroundImage;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final showBorder = variant == AppSurfaceVariant.outlined;
    final showShadow =
        variant == AppSurfaceVariant.card ||
        variant == AppSurfaceVariant.elevated;
    final resolvedColor =
        backgroundColor ??
        switch (variant) {
          AppSurfaceVariant.card ||
          AppSurfaceVariant.elevated => AppColors.surfaceCard,
          AppSurfaceVariant.tinted => AppColors.surfaceSoft,
          _ => AppColors.surfacePrimary,
        };
    final resolvedBorderColor = borderColor ?? AppColors.borderSubtle;

    final decoration = BoxDecoration(
      color: resolvedColor,
      borderRadius: BorderRadius.circular(borderRadius),
      border: showBorder
          ? Border.all(color: resolvedBorderColor, width: borderWidth)
          : null,
      boxShadow: boxShadow ?? (showShadow ? AppShadows.card : null),
      image: backgroundImage,
    );

    if (onPressed == null) {
      return Container(
        width: width,
        height: height,
        padding: padding,
        decoration: decoration,
        child: child,
      );
    }

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Container(
        width: width,
        height: height,
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class AppPanel extends StatelessWidget {
  const AppPanel({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(15),
    this.onPressed,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      width: double.infinity,
      padding: padding,
      borderRadius: 17,
      variant: AppSurfaceVariant.card,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}
