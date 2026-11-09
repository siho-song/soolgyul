import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_icon.dart';

/// 섹션 제목 오른쪽에 표시하는 공통 텍스트 액션입니다.
///
/// 홈처럼 상위 카드 전체가 눌리는 경우에는 [onPressed] 없이 표시하고,
/// 탐색처럼 액션 자체가 눌리는 경우에는 [onPressed]를 전달합니다.
class AppSectionAction extends StatelessWidget {
  const AppSectionAction({
    required this.label,
    super.key,
    this.onPressed,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  Widget get _content => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(label, style: AppTextStyles.sectionAction),
      const SizedBox(width: 5),
      const AppIcon(
        AppIconAsset.next,
        size: 15,
        color: AppColors.actionPrimaryStrong,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) {
      return _content;
    }

    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.minimumTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Center(child: _content),
            ),
          ),
        ),
      ),
    );
  }
}
