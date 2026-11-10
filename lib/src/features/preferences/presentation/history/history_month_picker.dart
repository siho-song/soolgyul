import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../widgets/app_date_wheel.dart';

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
) async {
  final picked = await showAppDateWheel(
    context,
    mode: CupertinoDatePickerMode.monthYear,
    initial: DateTime(initialMonth.year, initialMonth.month),
    minimum: DateTime(2020),
    maximum: DateTime.now(),
    wheelKey: const ValueKey<String>('history-cupertino-month-picker'),
  );
  return picked == null ? null : DateTime(picked.year, picked.month);
}
