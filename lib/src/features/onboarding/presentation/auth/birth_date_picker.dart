import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../profile/account_completion_draft.dart';

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
) {
  var pending = initial;
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (context) => Container(
      height: 320,
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: <Widget>[
                  CupertinoButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('취소'),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    key: const ValueKey<String>('birth-date-confirm'),
                    onPressed: () => Navigator.of(context).pop(pending),
                    child: const Text('확인'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                key: const ValueKey<String>('birth-date-wheel'),
                mode: CupertinoDatePickerMode.date,
                initialDateTime: initial,
                minimumDate: earliest,
                maximumDate: latest,
                onDateTimeChanged: (date) {
                  pending = DateTime(date.year, date.month, date.day);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
