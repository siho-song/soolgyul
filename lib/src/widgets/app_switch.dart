import 'package:flutter/material.dart';

import '../design/app_tokens.dart';

class AppSwitch extends StatelessWidget {
  const AppSwitch({
    required this.value,
    required this.onChanged,
    super.key,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      toggled: value,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.textOnPrimary,
        activeTrackColor: AppColors.actionPrimary,
        inactiveThumbColor: AppColors.textOnPrimary,
        inactiveTrackColor: AppColors.controlInactive,
      ),
    );
  }
}
