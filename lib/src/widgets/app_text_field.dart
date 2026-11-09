import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_icon.dart';
import 'app_icon_button.dart';

enum AppTextFieldVariant { outlined, search, plain }

enum AppTextFieldSize { compact, medium, large, journal }

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.initialValue,
    this.hintText,
    this.helperText,
    this.onChanged,
    this.onFieldSubmitted,
    this.onClear,
    this.validator,
    this.inputFormatters,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.textStyle,
    this.hintStyle,
    this.variant = AppTextFieldVariant.outlined,
    this.size = AppTextFieldSize.medium,
    this.isLoading = false,
    this.trailing,
  }) : assert(controller == null || initialValue == null);

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? initialValue;
  final String? hintText;
  final String? helperText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final VoidCallback? onClear;
  final FormFieldValidator<String>? validator;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;
  final AppTextFieldVariant variant;
  final AppTextFieldSize size;

  /// Shows a small spinner at the trailing edge, before the clear button.
  final bool isLoading;

  /// A widget at the very end of the field, after the clear button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final metrics = _TextFieldMetrics.fromSize(size);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(
        variant == AppTextFieldVariant.search ? 16 : AppRadii.control,
      ),
      borderSide: BorderSide(
        color: variant == AppTextFieldVariant.search
            ? AppColors.actionPrimaryStrong
            : AppColors.borderControl,
        width: variant == AppTextFieldVariant.search ? 1.3 : 1,
      ),
    );
    final focusedBorder = border.copyWith(
      borderSide: const BorderSide(color: AppColors.actionPrimary, width: 1.6),
    );

    final field = TextFormField(
      controller: controller,
      focusNode: focusNode,
      initialValue: initialValue,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      maxLines: maxLines,
      minLines: minLines,
      expands: expands,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      textAlign: textAlign,
      textAlignVertical: textAlignVertical,
      style: textStyle ?? metrics.textStyle,
      decoration: InputDecoration(
        hintText: hintText,
        helperText: helperText,
        counterText: maxLength == null ? null : '',
        hintStyle: hintStyle ?? metrics.hintStyle,
        isCollapsed: variant == AppTextFieldVariant.plain,
        filled: variant != AppTextFieldVariant.plain,
        // Search fields share the home cards' surface (see AppPanel).
        fillColor: variant == AppTextFieldVariant.search
            ? AppColors.surfaceCard
            : AppColors.surfacePrimary,
        contentPadding: variant == AppTextFieldVariant.plain
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(
                horizontal: 16,
                vertical: metrics.verticalPadding,
              ),
        prefixIcon: variant == AppTextFieldVariant.search
            ? const Padding(
                padding: EdgeInsets.all(15),
                child: AppIcon(
                  AppIconAsset.search,
                  size: 24,
                  color: AppColors.actionPrimaryStrong,
                  weight: AppIconWeight.strong,
                ),
              )
            : null,
        suffixIcon: onClear == null && !isLoading && trailing == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (isLoading)
                    Padding(
                      padding: EdgeInsets.only(right: onClear == null ? 16 : 4),
                      child: const SizedBox.square(
                        key: ValueKey<String>('app-text-field-loading'),
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.actionPrimaryStrong,
                        ),
                      ),
                    ),
                  if (onClear != null)
                    AppIconButton(
                      icon: AppIconAsset.close,
                      tooltip: '검색어 지우기',
                      onPressed: onClear,
                      size: AppIconButtonSize.compact,
                      tone: AppIconButtonTone.neutral,
                    ),
                  if (trailing case final trailing?)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: trailing,
                    ),
                ],
              ),
        border: variant == AppTextFieldVariant.plain
            ? InputBorder.none
            : border,
        enabledBorder: variant == AppTextFieldVariant.plain
            ? InputBorder.none
            : border,
        focusedBorder: variant == AppTextFieldVariant.plain
            ? InputBorder.none
            : focusedBorder,
      ),
    );
    if (variant != AppTextFieldVariant.search) {
      return field;
    }
    // The same soft shadow as the home cards, drawn behind the field.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: field,
    );
  }
}

class _TextFieldMetrics {
  const _TextFieldMetrics({
    required this.textStyle,
    required this.hintStyle,
    required this.verticalPadding,
  });

  factory _TextFieldMetrics.fromSize(AppTextFieldSize size) {
    return switch (size) {
      AppTextFieldSize.compact => _TextFieldMetrics(
        textStyle: AppTextStyles.body.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: AppTextStyles.body.copyWith(
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w500,
        ),
        verticalPadding: 14,
      ),
      AppTextFieldSize.medium => const _TextFieldMetrics(
        textStyle: AppTextStyles.textFieldText,
        hintStyle: AppTextStyles.textFieldHint,
        verticalPadding: 18,
      ),
      AppTextFieldSize.large => const _TextFieldMetrics(
        textStyle: AppTextStyle(fontSize: 16, color: AppColors.textPrimary),
        hintStyle: AppTextStyle(fontSize: 16, color: AppColors.textTertiary),
        verticalPadding: 12,
      ),
      AppTextFieldSize.journal => const _TextFieldMetrics(
        textStyle: AppTextStyle(
          fontSize: 27,
          height: 1.72,
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        hintStyle: AppTextStyle(
          fontSize: 27,
          height: 1.72,
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w800,
          color: AppColors.textTertiary,
        ),
        verticalPadding: 20,
      ),
    };
  }

  final TextStyle textStyle;
  final TextStyle hintStyle;
  final double verticalPadding;
}
