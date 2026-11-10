import 'package:flutter/cupertino.dart';

import '../design/app_tokens.dart';

/// iOS's date wheel in a bottom sheet with 취소 and 확인. Gives the date on
/// the wheel when 확인 is pressed, null when dismissed.
Future<DateTime?> showAppDateWheel(
  BuildContext context, {
  required DateTime initial,
  required DateTime minimum,
  required DateTime maximum,
  CupertinoDatePickerMode mode = CupertinoDatePickerMode.date,
  Key? wheelKey,
  Key? confirmKey,
}) {
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
                    key: confirmKey,
                    onPressed: () => Navigator.of(context).pop(pending),
                    child: const Text('확인'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                key: wheelKey,
                mode: mode,
                initialDateTime: initial,
                minimumDate: minimum,
                maximumDate: maximum,
                onDateTimeChanged: (date) => pending = date,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
