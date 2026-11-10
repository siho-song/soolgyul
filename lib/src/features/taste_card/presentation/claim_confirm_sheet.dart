import 'package:flutter/material.dart';

import '../../../widgets/app_button.dart';
import '../../../widgets/app_sheet.dart';

/// Asked before a card that arrived by link goes into the signed-in
/// account. A link can be written by anyone, so opening one must not put
/// a card among a person's records without their say.
class ClaimConfirmSheet extends StatelessWidget {
  const ClaimConfirmSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSheetBody(
      title: '이 카드를 내 기록에 담을까요?',
      body: '웹에서 만든 술결 카드를 지금 로그인한 계정의 기록으로 가져와요.',
      children: <Widget>[
        AppButton(
          key: const ValueKey<String>('claim-confirm-accept'),
          label: '담기',
          onPressed: () => Navigator.of(context).pop(true),
        ),
        AppButton(
          key: const ValueKey<String>('claim-confirm-decline'),
          label: '취소',
          variant: AppButtonVariant.tertiary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
