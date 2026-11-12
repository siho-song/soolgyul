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
      outlineVariant: AppColors.borderSubtle,
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
        size: AppSizes.iconLg,
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
      // Every button that is only words (다시 시도, 더 보기, 최신순) reads the
      // same: deep wine, 13px bold.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.actionPrimaryStrong,
          textStyle: const TextStyle(
            fontFamily: AppFonts.body,
            fontFamilyFallback: AppFonts.fallback,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
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
      // A light card over the page: see `showAppSnackBar`.
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfacePrimary,
        elevation: 6,
        actionTextColor: AppColors.actionPrimaryStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
          side: BorderSide(color: AppColors.borderSubtle),
        ),
        contentTextStyle: TextStyle(
          fontFamily: AppFonts.body,
          fontFamilyFallback: AppFonts.fallback,
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      // A press dims the control under the finger; no ripple spreads.
      splashFactory: NoSplash.splashFactory,
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

/// Every screen draws its text at the size it was designed at: the phone's
/// font-size setting does not enlarge it, so no layout breaks at a large
/// system size. Each app root passes this as its builder.
Widget fixedTextScale(BuildContext context, Widget? child) =>
    MediaQuery.withNoTextScaling(child: child ?? const SizedBox.shrink());
