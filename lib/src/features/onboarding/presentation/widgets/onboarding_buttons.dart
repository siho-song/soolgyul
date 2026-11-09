import 'package:flutter/material.dart';
import '../../../../widgets/app_brand_logo.dart';
import '../../../../widgets/app_button.dart';

class OnboardingBrandHeader extends StatelessWidget {
  const OnboardingBrandHeader({super.key, this.centered = false});

  final bool centered;

  @override
  Widget build(BuildContext context) {
    const brand = AppBrandLogo(size: AppBrandLogoSize.medium);
    return centered ? Align(alignment: Alignment.center, child: brand) : brand;
  }
}

class OnboardingPrimaryButton extends StatelessWidget {
  const OnboardingPrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      size: AppButtonSize.prominent,
      onPressed: onPressed,
    );
  }
}
