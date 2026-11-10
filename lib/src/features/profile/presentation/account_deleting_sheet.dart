import 'package:flutter/material.dart';

import '../../../widgets/app_button.dart';
import '../../../widgets/app_sheet.dart';

/// Shown when a signed-in session belongs to an account whose 30 days are
/// over but which the server has not deleted yet. Signing in within the 30
/// days restores the account without asking, so this is the only case left
/// to explain: it can be neither restored nor signed up again until the
/// deletion is finished.
class AccountDeletingSheet extends StatelessWidget {
  const AccountDeletingSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AppSheetBody(
        hasHandle: false,
        title: '계정을 삭제하고 있어요',
        body:
            '복구할 수 있는 기간이 끝났어요.\n\n'
            '삭제는 보통 1시간 안에 끝나고, 그 뒤에 다시 가입할 수 있어요.',
        children: <Widget>[
          AppButton(
            key: const ValueKey('account-deleting-confirm'),
            label: '확인',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
