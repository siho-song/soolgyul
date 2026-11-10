import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../../design/app_tokens.dart';
import '../../../auth/data/social_auth_service.dart';
import '../../../../widgets/app_snack_bar.dart';
import '../../../../core/errors/error_report.dart';

class SocialLoginActions extends StatefulWidget {
  const SocialLoginActions({required this.onLogin, super.key});

  final Future<void> Function(SocialAuthProvider provider) onLogin;

  @override
  State<SocialLoginActions> createState() => _SocialLoginActionsState();
}

class _SocialLoginActionsState extends State<SocialLoginActions> {
  SocialAuthProvider? _loadingProvider;

  Future<void> _login(SocialAuthProvider provider) async {
    if (_loadingProvider != null) {
      return;
    }

    setState(() => _loadingProvider = provider);
    try {
      await widget.onLogin(provider);
    } on SocialAuthCancelledException {
      // Cancellation is an expected end to the provider flow.
    } catch (error, stack) {
      reportError(error, stack, where: 'login');
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, '로그인에 실패했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) {
        setState(() => _loadingProvider = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _loadingProvider != null;
    final kakaoButton = _KakaoLoginButton(
      isLoading: _loadingProvider == SocialAuthProvider.kakao,
      onPressed: isBusy ? null : () => _login(SocialAuthProvider.kakao),
    );
    final appleButton = _BrandedLoginButton(
      buttonKey: const ValueKey<String>('apple-login-button'),
      label: 'Apple로 계속하기',
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      isLoading: _loadingProvider == SocialAuthProvider.apple,
      onPressed: isBusy ? null : () => _login(SocialAuthProvider.apple),
      icon: const SizedBox(
        key: ValueKey<String>('apple-login-icon'),
        width: 20,
        height: 24,
        child: CustomPaint(painter: AppleLogoPainter(color: Colors.white)),
      ),
    );
    final googleButton = _BrandedLoginButton(
      buttonKey: const ValueKey<String>('google-login-button'),
      label: 'Google로 계속하기',
      backgroundColor: isBusy ? const Color(0xFFF5F5F5) : Colors.white,
      foregroundColor: const Color(0xFF1F1F1F),
      borderColor: const Color(0xFF747775),
      isLoading: _loadingProvider == SocialAuthProvider.google,
      onPressed: isBusy ? null : () => _login(SocialAuthProvider.google),
      icon: Center(
        child: Image.asset(
          'assets/images/login/login_google_icon.png',
          key: const ValueKey<String>('google-login-icon'),
          width: 20,
          height: 20,
          fit: BoxFit.contain,
        ),
      ),
    );
    final usesIosOrder = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final secondaryButtons = usesIosOrder
        ? <Widget>[appleButton, googleButton]
        : <Widget>[googleButton, appleButton];

    return Column(
      children: <Widget>[
        kakaoButton,
        for (final button in secondaryButtons) ...<Widget>[
          const SizedBox(height: 10),
          button,
        ],
      ],
    );
  }
}

class _KakaoLoginButton extends StatelessWidget {
  const _KakaoLoginButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: '카카오로 시작하기',
      child: Opacity(
        opacity: onPressed == null ? .55 : 1,
        child: SizedBox(
          key: const ValueKey<String>('kakao-login-button'),
          width: double.infinity,
          height: 52,
          child: Material(
            color: const Color(0xFFFEE500),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              overlayColor: const WidgetStatePropertyAll<Color>(
                Colors.transparent,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Image.asset(
                        'assets/images/login/login_kakao_official.png',
                        key: const ValueKey<String>('kakao-login-artwork'),
                        width: 300,
                        height: 45,
                        fit: BoxFit.fill,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                  if (isLoading)
                    const Positioned(
                      right: 20,
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandedLoginButton extends StatelessWidget {
  const _BrandedLoginButton({
    required this.buttonKey,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.isLoading,
    required this.onPressed,
    this.borderColor,
  });

  final Key buttonKey;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final Widget icon;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: Opacity(
        opacity: onPressed == null ? .55 : 1,
        child: SizedBox(
          key: buttonKey,
          width: double.infinity,
          height: 52,
          child: Material(
            color: backgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: borderColor == null
                  ? BorderSide.none
                  : BorderSide(color: borderColor!),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: ExcludeSemantics(
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Positioned(
                      left: 20,
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: Center(child: icon),
                      ),
                    ),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppFonts.body,
                        fontSize: 15,
                        height: 20 / 15,
                        fontWeight: FontWeight.w500,
                        color: foregroundColor,
                        letterSpacing: 0,
                      ),
                    ),
                    if (isLoading)
                      Positioned(
                        right: 20,
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: foregroundColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
