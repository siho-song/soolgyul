part of '../taste_card_screen.dart';

// 카드 아래 홈으로 가는 버튼, 그리고 웹의 하단 고정 앱 안내 바입니다.

class _CardActions extends StatelessWidget {
  const _CardActions({required this.onSave});

  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: 58,
        child: AppButton(
          key: const ValueKey<String>('save-preference-button'),
          label: '홈으로',
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
            label: '술결 앱에서 확인하기',
            onPressed: onPressed,
            variant: AppButtonVariant.accent,
            size: AppButtonSize.prominent,
          ),
        ),
      ),
    ),
  );
}
