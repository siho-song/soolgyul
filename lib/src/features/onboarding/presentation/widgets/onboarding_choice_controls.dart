import '../../../../widgets/app_selection_mark.dart';
import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_chip.dart';

class OnboardingLargeOption extends StatelessWidget {
  const OnboardingLargeOption({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 70),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  AnimatedContainer(
                    key: ValueKey<String>('selection-marker-$label'),
                    duration: AppDurations.fast,
                    width: 4,
                    height: selected ? 44 : 0,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.actionPrimary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadii.chip),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.s14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IntrinsicWidth(
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: <Widget>[
                                  Text(
                                    label,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: selected
                                        ? AppTextStyles
                                              .onboardingOptionLabelSelected
                                        : AppTextStyles.onboardingOptionLabel,
                                  ),
                                  Positioned(
                                    left: -1,
                                    right: -24,
                                    bottom: -12,
                                    height: 7,
                                    child: IgnorePointer(
                                      child: AnimatedOpacity(
                                        duration: AppDurations.fast,
                                        opacity: selected ? 1 : 0,
                                        child: Image.asset(
                                          'assets/images/onboarding/'
                                          'onboarding_selected_brush_underline.png',
                                          key: ValueKey<String>(
                                            'selection-underline-$label',
                                          ),
                                          fit: BoxFit.fill,
                                          filterQuality: FilterQuality.high,
                                          excludeFromSemantics: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppSelectionMark(selected: selected),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 질문 화면의 선택지 칩 크기. 향 칩과 확인 화면의 칩이 이 하나를 씁니다.
const onboardingChoiceChipSize = AppChipSize.filter;
