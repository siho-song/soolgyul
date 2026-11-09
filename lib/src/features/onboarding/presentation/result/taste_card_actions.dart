part of '../onboarding_result_screen.dart';

// 카드 아래 저장 버튼, 그리고 웹의 하단 고정 앱 안내 바입니다.

class _CardActions extends StatelessWidget {
  const _CardActions({required this.onSave, required this.isSaved});

  final VoidCallback onSave;
  final bool isSaved;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: 58,
        child: AppButton(
          key: const ValueKey<String>('save-preference-button'),
          label: isSaved ? '저장 완료' : '내 술결 저장하기',
          onPressed: onSave,
          variant: AppButtonVariant.accent,
          size: AppButtonSize.prominent,
        ),
      ),
    );
  }
}

/// The web's one action under the card, fixed at the bottom while the card
/// scrolls: the visitor's card lives on in the app.
class _OpenAppBar extends StatelessWidget {
  const _OpenAppBar({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: _TasteCardColors.canvas,
      border: Border(top: BorderSide(color: _TasteCardColors.ticketLine)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
        child: SizedBox(
          height: 58,
          child: AppButton(
            key: const ValueKey<String>('open-app-button'),
            label: '앱에서 내 술결 확인하기',
            onPressed: onPressed,
            variant: AppButtonVariant.accent,
            size: AppButtonSize.prominent,
          ),
        ),
      ),
    ),
  );
}
