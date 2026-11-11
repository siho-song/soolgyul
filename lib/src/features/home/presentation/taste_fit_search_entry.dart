import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_icon.dart';
import '../../taste_fit/presentation/widgets/label_scan_button.dart';

/// Looks like the app's search field; tapping opens the taste-fit search.
/// With [onScanLabel] a small camera button sits at its end for readers who
/// would rather photograph the label than type its name; the section text
/// above the field already explains it, so the button carries no caption.
class TasteFitSearchEntry extends StatelessWidget {
  const TasteFitSearchEntry({
    required this.onOpen,
    this.onScanLabel,
    super.key,
  });

  static const String placeholder = '술 이름이나 브랜드 검색';
  static const String scanLabelHint = '라벨 사진으로 찾기';

  final VoidCallback onOpen;
  final VoidCallback? onScanLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '내게 맞는 술 검색창',
      child: Material(
        color: Colors.white.withValues(alpha: .72),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          side: const BorderSide(
            color: AppColors.actionPrimaryStrong,
            width: 1.3,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 50,
          child: Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  key: const ValueKey<String>('home-taste-fit-entry'),
                  onTap: onOpen,
                  child: const Row(
                    children: <Widget>[
                      SizedBox(width: AppSpacing.lg),
                      AppIcon(
                        AppIconAsset.search,
                        size: AppSizes.iconLg,
                        color: AppColors.actionPrimaryStrong,
                      ),
                      SizedBox(width: AppSpacing.s10),
                      Expanded(
                        child: Text(
                          placeholder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.textFieldHint,
                        ),
                      ),
                      SizedBox(width: AppSpacing.s10),
                    ],
                  ),
                ),
              ),
              if (onScanLabel case final scan?)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: LabelScanButton(
                    key: const ValueKey<String>('home-taste-fit-label'),
                    label: scanLabelHint,
                    onPressed: scan,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
