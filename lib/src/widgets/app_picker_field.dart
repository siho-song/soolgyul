import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_icon.dart';

/// The height of a field that opens a picker or a list of choices.
const double appPickerFieldHeight = 54;

/// The arrow at the right of a field that opens a picker or a list.
const Widget appPickerArrow = Icon(
  Icons.expand_more,
  size: AppSizes.iconMd,
  color: AppColors.textTertiary,
);

/// The white, thinly bordered look of a field that opens a list of choices,
/// the same as [AppPickerField].
InputDecoration appPickerDecoration({String? hintText}) => InputDecoration(
  hintText: hintText,
  hintStyle: AppTextStyles.textFieldHint,
  filled: true,
  fillColor: AppColors.surfacePrimary,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.s14,
    vertical: AppSpacing.lg,
  ),
  border: _border(AppColors.borderSubtle, 1),
  enabledBorder: _border(AppColors.borderSubtle, 1),
  disabledBorder: _border(AppColors.borderSubtle, 1),
  focusedBorder: _border(AppColors.actionPrimary, 1.6),
);

OutlineInputBorder _border(Color color, double width) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(AppRadii.control),
  borderSide: BorderSide(color: color, width: width),
);

/// A tappable field that looks like the app's text field and opens a picker.
class AppPickerField extends StatelessWidget {
  const AppPickerField({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
    super.key,
  });

  final AppIconAsset icon;
  final String label;

  /// Whether [label] is a chosen value, not the hint.
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = filled ? AppColors.textPrimary : AppColors.textTertiary;
    return SizedBox(
      height: appPickerFieldHeight,
      child: Material(
        color: AppColors.surfacePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          side: const BorderSide(color: AppColors.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s14,
              0,
              AppSpacing.md,
              0,
            ),
            child: Row(
              children: <Widget>[
                AppIcon(icon, size: AppSizes.iconMd, color: color),
                const SizedBox(width: AppSpacing.s10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.textFieldText.copyWith(
                      height: null,
                      color: color,
                    ),
                  ),
                ),
                appPickerArrow,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
