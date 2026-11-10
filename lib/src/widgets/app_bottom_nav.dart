import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_icon.dart';

enum AppTab { home, preference, record, explore, profile }

enum AppRecordIntent { openTab, startFlow }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.activeTab,
    required this.onTab,
    required this.onRecord,
    this.recordIntent = AppRecordIntent.openTab,
    this.recordLabel,
  });

  final AppTab activeTab;
  final ValueChanged<AppTab> onTab;
  final ValueChanged<AppRecordIntent> onRecord;
  final AppRecordIntent recordIntent;
  final String? recordLabel;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final accessibleHeight = AppSpacing.navHeight + ((textScale - 1) * 40);
    return SafeArea(
      top: false,
      child: Container(
        height: accessibleHeight,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFEDEAE7))),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 12,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            AppBottomNavItem(
              icon: AppIconAsset.home,
              label: '홈',
              tab: AppTab.home,
              active: activeTab == AppTab.home,
              onTap: onTab,
            ),
            AppBottomNavItem(
              icon: AppIconAsset.tasteDiscovery,
              label: '취향',
              tab: AppTab.preference,
              active: activeTab == AppTab.preference,
              onTap: onTab,
            ),
            AppRecordNavItem(
              label: recordLabel ?? '기록',
              onTap: () => onRecord(recordIntent),
            ),
            AppBottomNavItem(
              icon: AppIconAsset.explore,
              label: '탐색',
              tab: AppTab.explore,
              active: activeTab == AppTab.explore,
              onTap: onTab,
            ),
            AppBottomNavItem(
              icon: AppIconAsset.profile,
              label: '마이페이지',
              tab: AppTab.profile,
              active: activeTab == AppTab.profile,
              onTap: onTab,
            ),
          ],
        ),
      ),
    );
  }
}

class AppRecordNavItem extends StatelessWidget {
  const AppRecordNavItem({super.key, required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => _NavSlot(
    icon: AppIconAsset.memo,
    label: label,
    color: AppColors.actionPrimary,
    bold: true,
    pop: true,
    onTap: onTap,
  );
}

class AppBottomNavItem extends StatelessWidget {
  const AppBottomNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final AppIconAsset icon;
  final String label;
  final AppTab tab;
  final bool active;
  final ValueChanged<AppTab> onTap;

  @override
  Widget build(BuildContext context) => _NavSlot(
    icon: icon,
    label: label,
    color: active ? AppColors.actionPrimary : AppColors.textTertiary,
    bold: active,
    pop: active,
    onTap: () => onTap(tab),
  );
}

/// One slot of the bar. The icon pops (shrinks, then springs past its size
/// and settles) each time the slot is tapped and whenever it becomes the
/// active tab, while icon and label colours cross-fade.
class _NavSlot extends StatefulWidget {
  const _NavSlot({
    required this.icon,
    required this.label,
    required this.color,
    required this.bold,
    required this.pop,
    required this.onTap,
  });

  final AppIconAsset icon;
  final String label;
  final Color color;
  final bool bold;

  /// Whether the slot is the one lit up; turning true plays the pop.
  final bool pop;
  final VoidCallback onTap;

  @override
  State<_NavSlot> createState() => _NavSlotState();
}

class _NavSlotState extends State<_NavSlot>
    with SingleTickerProviderStateMixin {
  static const _popDuration = Duration(milliseconds: 360);
  static const _colorDuration = Duration(milliseconds: 180);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _popDuration,
  );
  late final Animation<double> _scale =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem(
          tween: Tween<double>(
            begin: 1,
            end: 0.82,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 35,
        ),
        TweenSequenceItem(
          tween: Tween<double>(
            begin: 0.82,
            end: 1.12,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 35,
        ),
        TweenSequenceItem(
          tween: Tween<double>(
            begin: 1.12,
            end: 1,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 30,
        ),
      ]).animate(_controller);

  @override
  void didUpdateWidget(covariant _NavSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pop && !oldWidget.pop) _play();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _play() => _controller.forward(from: 0);

  void _handleTap() {
    // A tap on the already lit slot pops too; a tap elsewhere pops once the
    // parent marks this slot active, so the same pop is not played twice.
    if (widget.pop) _play();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: _handleTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          ScaleTransition(
            scale: _scale,
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: widget.color),
              duration: _colorDuration,
              builder: (context, color, _) => AppIcon(
                widget.icon,
                color: color,
                size: 29,
                weight: AppIconWeight.medium,
              ),
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: _colorDuration,
            style: AppTextStyle(
              fontSize: 12,
              color: widget.color,
              fontWeight: widget.bold ? FontWeight.w800 : FontWeight.w500,
            ),
            child: Text(widget.label),
          ),
        ],
      ),
    ),
  );
}
