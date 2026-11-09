import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'app_typography.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      primary: AppColors.actionPrimary,
      onPrimary: AppColors.textOnPrimary,
      secondary: AppColors.actionPrimaryStrong,
      onSecondary: AppColors.textOnPrimary,
      surface: AppColors.surfaceCanvas,
      onSurface: AppColors.textPrimary,
      error: Color(0xFFBA1A1A),
      onError: AppColors.textOnPrimary,
      outline: AppColors.borderSubtle,
      outlineVariant: AppColors.borderMuted,
      shadow: Color(0x24000000),
      scrim: AppColors.scrim,
    );
    final defaultTextTheme =
        ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: colorScheme,
          fontFamily: AppFonts.body,
          fontFamilyFallback: AppFonts.fallback,
        ).textTheme.apply(
          fontFamily: AppFonts.body,
          fontFamilyFallback: AppFonts.fallback,
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: AppFonts.body,
      fontFamilyFallback: AppFonts.fallback,
      scaffoldBackgroundColor: AppColors.surfaceCanvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      colorScheme: colorScheme,
      textTheme: defaultTextTheme,
      iconTheme: const IconThemeData(
        color: AppColors.textPrimary,
        size: AppSizes.iconMedium,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfacePrimary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: _inputBorder(AppColors.borderSubtle),
        enabledBorder: _inputBorder(AppColors.borderSubtle),
        focusedBorder: _inputBorder(AppColors.actionPrimary, width: 1.4),
        errorBorder: _inputBorder(colorScheme.error),
        focusedErrorBorder: _inputBorder(colorScheme.error, width: 1.4),
        hintStyle: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.largeCard)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: TextStyle(color: AppColors.textOnPrimary),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
