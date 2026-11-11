import 'package:flutter/material.dart';
import '../../../../widgets/app_date_wheel.dart';
import '../../../profile/data/account_completion_draft.dart';

/// Asks for a birth date with the platform's picker: a wheel sheet on iOS,
/// the Material calendar elsewhere. Null when dismissed.
Future<DateTime?> showBirthDatePicker(
  BuildContext context, {
  DateTime? initialDate,
}) {
  final latest = DateTime(
    AccountCompletionDraft.latestEligibleBirthYear(),
    12,
    31,
  );
  final earliest = DateTime(AccountCompletionDraft.oldestBirthYear);
  final initial = initialDate == null || initialDate.isAfter(latest)
      ? DateTime(latest.year)
      : initialDate;
  return Theme.of(context).platform == TargetPlatform.iOS
      ? _showCupertinoBirthDatePicker(context, initial, earliest, latest)
      : showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: earliest,
          lastDate: latest,
          helpText: '생년월일 선택',
          confirmText: '확인',
          cancelText: '취소',
        );
}

Future<DateTime?> _showCupertinoBirthDatePicker(
  BuildContext context,
  DateTime initial,
  DateTime earliest,
  DateTime latest,
) async {
  final picked = await showAppDateWheel(
    context,
    initial: initial,
    minimum: earliest,
    maximum: latest,
    wheelKey: const ValueKey<String>('birth-date-wheel'),
    confirmKey: const ValueKey<String>('birth-date-confirm'),
  );
  return picked == null
      ? null
      : DateTime(picked.year, picked.month, picked.day);
}
