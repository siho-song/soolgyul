import 'package:flutter/material.dart';

import '../../../design/app_layout.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/edge_fade.dart';
import 'widgets/onboarding_layout.dart';

/// The first onboarding page: the value line and one button that opens the
/// drink-name question on its own page.
class OnboardingWelcomeScreen extends StatelessWidget {
  const OnboardingWelcomeScreen({required this.onStart, super.key});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return OnboardingScrollableBody(
      topPadding: AppSpacing.sm,
      builder: (context, layout) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          OnboardingWelcomeHero(
            compact: layout.screenWidth < AppLayout.compactPhoneWidth,
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxl),
            child: AppButton(
              key: const ValueKey<String>('onboarding-welcome-start'),
              label: '시작하기',
              size: AppButtonSize.prominent,
              onPressed: onStart,
            ),
          ),
        ],
      ),
    );
  }
}

/// The welcome image and value line on the first onboarding page.
class OnboardingWelcomeHero extends StatelessWidget {
  const OnboardingWelcomeHero({required this.compact, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    const imageAspectRatio = 864 / 992;
    final imageHeight = compact ? 92.0 : 248.0;
    final imageWidth = imageHeight * imageAspectRatio;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned(
          key: const ValueKey<String>('onboarding-welcome-image-layer'),
          right: -AppSpacing.screenX,
          bottom: 0,
          width: imageWidth,
          height: imageHeight,
          child: EdgeFade(
            child: Image.asset(
              'assets/images/onboarding/'
              'onboarding_welcome_reflection_faded.png',
              key: const ValueKey<String>('onboarding-welcome-image'),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
        ),
        Positioned(
          key: const ValueKey<String>('onboarding-welcome-image-fade'),
          left: 0,
          right: -AppSpacing.screenX,
          bottom: 0,
          height: imageHeight,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    AppColors.surfaceCanvas,
                    Color.fromRGBO(251, 246, 240, .96),
                    Color.fromRGBO(251, 246, 240, .42),
                    Color.fromRGBO(251, 246, 240, .04),
                  ],
                  stops: <double>[0, .42, .72, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          key: const ValueKey<String>('onboarding-welcome-image-top-fade'),
          left: 0,
          right: -AppSpacing.screenX,
          bottom: 0,
          height: imageHeight,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    AppColors.surfaceCanvas,
                    Color.fromRGBO(251, 246, 240, .72),
                    Color.fromRGBO(251, 246, 240, 0),
                  ],
                  stops: <double>[0, .18, .34],
                ),
              ),
            ),
          ),
        ),
        Container(
          key: const ValueKey<String>('onboarding-welcome-copy-layer'),
          width: double.infinity,
          padding: EdgeInsets.only(
            top: compact ? 10 : 24,
            bottom: compact ? 0 : AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '나에게 맞는 술을 몰라\n고르기 힘든 적 있으셨죠?',
                style: AppTextStyles.onboardingTitle,
              ),
              SizedBox(height: compact ? AppSpacing.sm : AppSpacing.lg),
              Text(
                '딱 1분, 내 취향 발견과 실패 없는 다음 술 가이드까지',
                style: AppTextStyles.onboardingLead,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
