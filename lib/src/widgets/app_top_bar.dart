import 'package:flutter/material.dart';

import '../design/app_layout.dart';
import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_icon.dart';
import 'app_icon_button.dart';

enum _AppTopBarLeading { back, none }

/// 앱 전역의 단일 헤더 규격입니다.
///
/// 모든 화면은 고객센터 헤더와 같은 64dp 높이, 17px 제목, 48dp 버튼,
/// 24dp 아이콘을 사용합니다. 화면별 크기와 색상 재정의는 허용하지 않습니다.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar.root({
    super.key,
    this.title,
    this.showDivider = false,
    this.actions = const <Widget>[],
    this.logoAlignment = Alignment.centerLeft,
  }) : _center = null,
       onPressed = null,
       _leading = _AppTopBarLeading.none;

  const AppTopBar.back({
    required this.onPressed,
    super.key,
    this.title,
    Widget? center,
    this.showDivider = false,
    this.actions = const <Widget>[],
  }) : assert(title == null || center == null),
       _center = center,
       logoAlignment = Alignment.center,
       _leading = _AppTopBarLeading.back;

  const AppTopBar.logo({
    required Widget logo,
    super.key,
    this.showDivider = false,
    this.actions = const <Widget>[],
    this.logoAlignment = Alignment.centerLeft,
  }) : title = null,
       _center = logo,
       onPressed = null,
       _leading = _AppTopBarLeading.none;

  final String? title;
  final Widget? _center;
  final VoidCallback? onPressed;
  final _AppTopBarLeading _leading;
  final bool showDivider;
  final List<Widget> actions;
  final Alignment logoAlignment;

  @override
  Size get preferredSize => const Size.fromHeight(AppSizes.headerHeight);

  @override
  Widget build(BuildContext context) {
    final titleHorizontalPadding = actions.isEmpty
        ? AppSizes.headerButton
        : AppSizes.headerButton * 2;

    return SafeArea(
      bottom: false,
      child: Container(
        height: AppSizes.headerHeight,
        decoration: BoxDecoration(
          color: AppColors.surfaceCanvas,
          border: showDivider
              ? const Border(bottom: BorderSide(color: AppColors.borderSubtle))
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppLayout.headerHorizontalPadding,
            vertical: 8,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              if (_leading != _AppTopBarLeading.none)
                Positioned(
                  left: 0,
                  top: 0,
                  child: AppIconButton(
                    icon: AppIconAsset.previous,
                    onPressed: onPressed,
                    tooltip: '이전 화면으로 이동',
                    size: AppIconButtonSize.medium,
                    tone: AppIconButtonTone.ink,
                  ),
                ),
              if (_leading == _AppTopBarLeading.none)
                Positioned.fill(
                  child: Align(
                    alignment: logoAlignment,
                    child:
                        _center ??
                        (title == null
                            ? const SizedBox.shrink()
                            : Text(
                                title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.appHeaderTitle,
                              )),
                  ),
                )
              else
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: titleHorizontalPadding,
                  ),
                  child:
                      _center ??
                      Text(
                        title ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.appHeaderTitle,
                      ),
                ),
              if (actions.isNotEmpty)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final action in actions)
                        _AppTopBarActionSlot(child: action),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Material 아이콘을 쓰는 헤더 액션도 공통 48/24 규격으로 맞춥니다.
class AppTopBarMaterialAction extends StatelessWidget {
  const AppTopBarMaterialAction({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    super.key,
    this.color = AppColors.textPrimary,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: AppSizes.headerButton,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(AppSizes.headerButton),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: AppSizes.headerIcon, color: color),
    ),
  );
}

/// A short text action at the header's right end, such as `SKIP`.
class AppTopBarTextAction extends StatelessWidget {
  const AppTopBarTextAction({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkResponse(
      onTap: onPressed,
      radius: AppSizes.headerButton / 2,
      child: SizedBox.square(
        dimension: AppSizes.headerButton,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            style: AppTextStyles.sectionAction.copyWith(fontSize: 14),
          ),
        ),
      ),
    ),
  );
}

class _AppTopBarActionSlot extends StatelessWidget {
  const _AppTopBarActionSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: AppSizes.headerButton,
    child: Center(child: child),
  );
}
