part of '../taste_card_screen.dart';

// 웹의 하단 고정 앱 안내 바입니다.

/// The web's one action under the card, fixed at the bottom while the card
/// scrolls: the visitor's card lives on in the app.
class _OpenAppBar extends StatelessWidget {
  const _OpenAppBar({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    // On the page's 한지 like the card above it, under one thin line.
    decoration: const BoxDecoration(
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
            label: '앱에서 확인하기',
            onPressed: onPressed,
            variant: AppButtonVariant.accent,
            size: AppButtonSize.prominent,
          ),
        ),
      ),
    ),
  );
}
