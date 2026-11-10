import 'package:flutter/material.dart';
import '../../../../design/app_layout.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/edge_fade.dart';
import '../../../auth/data/social_auth_service.dart';
import 'social_login_actions.dart';

/// The app's login, the first page it shows without a session. The web
/// never logs in: its onboarding ends by sending the visitor to the app.
class OnboardingLoginScreen extends StatelessWidget {
  const OnboardingLoginScreen({required this.onLogin, super.key});

  final Future<void> Function(SocialAuthProvider provider) onLogin;

  static const _headline = '내 취향을 발견하고,\n딱 맞는 한 잔을 찾아보세요.';
  static const _description = '지금 로그인하고 첫 테이스팅을 기록해 보세요.';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!AppLayout.isViewportReady(constraints)) {
          return const SizedBox.shrink();
        }

        final screenLayout = AppScreenLayout.fromConstraints(constraints);
        final horizontalPadding = screenLayout.horizontalPadding;
        const topPadding = 24.0;
        final heroHeight = screenLayout.scaledHeight(
          ratio: .25,
          minimum: 210,
          maximum: 280,
        );

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const Text(
                _headline,
                textAlign: TextAlign.center,
                style: AppTextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: AppColors.textStrong,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              EdgeFade(
                top: .1,
                bottom: .2,
                sides: .08,
                child: Image.asset(
                  'assets/component_assets/login_hero.png',
                  height: heroHeight,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 34),
              const Text(
                '간편하게 시작하기',
                textAlign: TextAlign.center,
                style: AppTextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                _description,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xxl),
              SocialLoginActions(onLogin: onLogin),
            ],
          ),
        );
      },
    );
  }
}
