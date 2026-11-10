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

/// 질문 화면의 선택지 칩 크기. 향·맛·느낌 칩이 모두 이 하나를 씁니다.
const onboardingChoiceChipSize = AppChipSize.filter;

/// 칩 하나의 내용입니다.
class OnboardingChoice {
  const OnboardingChoice({
    required this.id,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
}

/// 이름이 짧은 선택지를 칩으로 보여 줍니다. 칩은 이름 길이만큼만 차지해서
/// 한 줄에 들어가는 만큼 나란히 놓입니다.
class OnboardingChipWrap extends StatelessWidget {
  const OnboardingChipWrap({
    required this.choices,
    this.size = onboardingChoiceChipSize,
    super.key,
  });

  final List<OnboardingChoice> choices;
  final AppChipSize size;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: <Widget>[
      for (final choice in choices)
        AppChip(
          key: ValueKey<String>(choice.id),
          label: choice.label,
          size: size,
          variant: AppChipVariant.outline,
          selected: choice.selected,
          onPressed: choice.onPressed,
        ),
    ],
  );
}

/// 선택지를 한 줄에 같은 폭으로 나란히 놓습니다. 세 반응처럼 개수가 정해진
/// 선택지가 줄바꿈 없이 한 줄을 채우게 할 때 씁니다.
class OnboardingChoiceColumns extends StatelessWidget {
  const OnboardingChoiceColumns({required this.choices, super.key});

  final List<OnboardingChoice> choices;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      for (final (index, choice) in choices.indexed) ...<Widget>[
        if (index > 0) const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppChip(
            key: ValueKey<String>(choice.id),
            label: choice.label,
            size: onboardingChoiceChipSize,
            variant: AppChipVariant.outline,
            selected: choice.selected,
            expand: true,
            onPressed: choice.onPressed,
          ),
        ),
      ],
    ],
  );
}

/// 한 항목에 좋았어요/적당했어요/아쉬웠어요 중 하나를 고르게 합니다. 세 버튼은
/// 한 줄을 3등분해 차지하고, 고른 반응에 [details]가 있으면 그 바로 아래에
/// 작은 칩(맛의 이유, 느낌의 방향)이 펼쳐집니다.
class OnboardingReactionPair extends StatelessWidget {
  const OnboardingReactionPair({
    required this.label,
    required this.liked,
    required this.fine,
    required this.disliked,
    this.details = const <OnboardingChoice>[],
    super.key,
  });

  final String label;
  final OnboardingChoice liked;

  /// 적당했어요: tastes and mouthfeel, the sections with a reaction page.
  final OnboardingChoice fine;
  final OnboardingChoice disliked;

  /// The follow-up chips of the chosen reaction; empty hides the row.
  final List<OnboardingChoice> details;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(label, style: AppTextStyles.onboardingOptionLabel),
        const SizedBox(height: AppSpacing.sm),
        OnboardingChoiceColumns(
          choices: <OnboardingChoice>[liked, fine, disliked],
        ),
        AnimatedSize(
          duration: AppDurations.standard,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: details.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    left: AppSpacing.md,
                  ),
                  child: OnboardingChipWrap(
                    choices: details,
                    size: AppChipSize.regular,
                  ),
                ),
        ),
      ],
    ),
  );
}
