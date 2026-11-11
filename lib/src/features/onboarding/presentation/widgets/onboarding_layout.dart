import 'package:flutter/material.dart';
import '../../../../design/app_layout.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/app_icon.dart';

typedef OnboardingContentBuilder =
    Widget Function(BuildContext context, AppScreenLayout layout);

typedef OnboardingChildrenBuilder =
    List<Widget> Function(BuildContext context, AppScreenLayout layout);

/// The page is at least the viewport tall, so a page whose content is short
/// can keep its buttons at the bottom with `MainAxisAlignment.spaceBetween`.
/// There is no `Spacer` and no intrinsic measuring: on the web, text whose
/// emoji fall back to another font measures a pixel shorter than it lays
/// out, which made an intrinsic-height column overflow by that pixel.
class OnboardingScrollableBody extends StatelessWidget {
  const OnboardingScrollableBody({
    required this.builder,
    super.key,
    this.topPadding = AppSpacing.xxl,
    this.bottomPadding = AppSpacing.xxl,
  });

  final OnboardingContentBuilder builder;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!AppLayout.isViewportReady(constraints)) {
          return const SizedBox.shrink();
        }

        final layout = AppScreenLayout.fromConstraints(constraints);
        return SingleChildScrollView(
          key: const ValueKey<String>('onboarding-page-scroll'),
          padding: EdgeInsets.fromLTRB(
            layout.horizontalPadding,
            topPadding,
            layout.horizontalPadding,
            bottomPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - topPadding - bottomPadding)
                  .clamp(0, double.infinity),
            ),
            child: builder(context, layout),
          ),
        );
      },
    );
  }
}

/// 온보딩 단계 하단 버튼 하나의 내용입니다.
class OnboardingStepAction {
  const OnboardingStepAction({
    required this.label,
    required this.onPressed,
    this.key,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Key? key;
  final AppIconAsset? trailingIcon;
}

/// 온보딩 단계의 공통 화면 골격입니다.
///
/// 화면별 구현은 문구와 본문, 하단 버튼 내용만 전달하고, 상단 패딩과
/// 질문 헤더, 본문 간격, 화면 아래에 붙는 버튼의 크기와 간격은 이
/// 위젯에서 일관되게 관리합니다.
/// Description to options on every question page; wider than the 8px
/// between title and description.
const _descriptionToOptionsGap = 28.0;

class OnboardingStepScaffold extends StatelessWidget {
  const OnboardingStepScaffold({
    required this.title,
    required this.description,
    required this.childrenBuilder,
    required this.primaryAction,
    super.key,
    this.secondaryAction,
    this.descriptionStyle,
    this.descriptionTrailing,
    this.descriptionContent,
    this.topContentBuilder,
    this.topPadding = AppSpacing.xxl,
    this.bottomPadding = AppSpacing.xxl,
  });

  final String title;
  final String description;
  final TextStyle? descriptionStyle;

  /// Short text at the end of the description line, such as a `2/5` count.
  final String? descriptionTrailing;

  /// Shown in place of the description text, such as a tap guide.
  final Widget? descriptionContent;
  final OnboardingContentBuilder? topContentBuilder;
  final OnboardingChildrenBuilder childrenBuilder;
  final OnboardingStepAction primaryAction;

  /// 다음 버튼 아래의 같은 크기 보조 버튼입니다. 건너뛰기처럼 단계를
  /// 넘기는 선택에 씁니다.
  final OnboardingStepAction? secondaryAction;
  final double topPadding;
  final double bottomPadding;

  Widget _button(OnboardingStepAction action, AppButtonVariant variant) =>
      AppButton(
        key: action.key,
        label: action.label,
        trailingIcon: action.trailingIcon,
        size: AppButtonSize.prominent,
        variant: variant,
        onPressed: action.onPressed,
      );

  @override
  Widget build(BuildContext context) {
    return OnboardingScrollableBody(
      topPadding: topPadding,
      bottomPadding: bottomPadding,
      builder: (context, layout) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (topContentBuilder != null) ...<Widget>[
                topContentBuilder!(context, layout),
                const SizedBox(height: AppSpacing.xxl),
              ],
              OnboardingQuestionHeader(
                title: title,
                description: description,
                descriptionStyle: descriptionStyle,
                descriptionTrailing: descriptionTrailing,
                descriptionContent: descriptionContent,
              ),
              const SizedBox(height: _descriptionToOptionsGap),
              ...childrenBuilder(context, layout),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: AppSpacing.xxl),
              _button(primaryAction, AppButtonVariant.primary),
              if (secondaryAction != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                _button(secondaryAction!, AppButtonVariant.secondary),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class OnboardingQuestionHeader extends StatelessWidget {
  const OnboardingQuestionHeader({
    required this.title,
    required this.description,
    super.key,
    this.descriptionStyle,
    this.descriptionTrailing,
    this.descriptionContent,
  });

  final String title;
  final String description;
  final TextStyle? descriptionStyle;
  final String? descriptionTrailing;
  final Widget? descriptionContent;

  @override
  Widget build(BuildContext context) {
    final body =
        descriptionContent ??
        Text(
          description,
          textAlign: TextAlign.start,
          style: descriptionStyle ?? AppTextStyles.onboardingBody,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: AppTextStyles.onboardingTitle),
        if (description.isNotEmpty || descriptionContent != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          if (descriptionTrailing case final trailing?)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(child: body),
                const SizedBox(width: AppSpacing.sm),
                Text(trailing, style: AppTextStyles.bodyMuted),
              ],
            )
          else
            body,
        ],
      ],
    );
  }
}
