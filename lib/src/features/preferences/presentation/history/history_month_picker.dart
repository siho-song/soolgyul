import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';

/// What the month control picked: Android's Material date picker picks a
/// day, iOS's Cupertino wheel only a month.
typedef HistoryPick = ({DateTime month, DateTime? day});

/// Asks with the platform's picker; null when dismissed.
Future<HistoryPick?> showHistoryMonthPicker(
  BuildContext context,
  DateTime initialDay,
) async {
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    final month = await _showCupertinoMonthPicker(context, initialDay);
    return month == null ? null : (month: month, day: null);
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = await showDatePicker(
    context: context,
    initialDate: initialDay.isAfter(today) ? today : initialDay,
    firstDate: DateTime(2020),
    lastDate: today,
    helpText: '날짜 선택',
  );
  return day == null ? null : (month: DateTime(day.year, day.month), day: day);
}

Future<DateTime?> _showCupertinoMonthPicker(
  BuildContext context,
  DateTime initialMonth,
) {
  var pendingMonth = DateTime(initialMonth.year, initialMonth.month);
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
                    onPressed: () => Navigator.of(context).pop(pendingMonth),
                    child: const Text('확인'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                key: const ValueKey<String>('history-cupertino-month-picker'),
                mode: CupertinoDatePickerMode.monthYear,
                initialDateTime: DateTime(
                  initialMonth.year,
                  initialMonth.month,
                ),
                minimumDate: DateTime(2020),
                maximumDate: DateTime.now(),
                onDateTimeChanged: (date) {
                  pendingMonth = DateTime(date.year, date.month);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
