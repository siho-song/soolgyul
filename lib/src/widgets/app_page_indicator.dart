import 'package:flutter/widgets.dart';

import '../design/app_tokens.dart';

class AppPageIndicator extends StatelessWidget {
  const AppPageIndicator({
    required this.count,
    required this.activeIndex,
    super.key,
    this.onSelected,
    this.dotSize = 7,
    this.dotSpacing = 4,
    this.activeColor = AppColors.actionPrimary,
    this.inactiveColor = AppColors.surfaceMuted,
  }) : assert(count > 0),
       assert(activeIndex >= 0 && activeIndex < count);

  final int count;
  final int activeIndex;
  final ValueChanged<int>? onSelected;
  final double dotSize;
  final double dotSpacing;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${activeIndex + 1} / $count',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (var index = 0; index < count; index++)
          Semantics(
            button: onSelected != null,
            selected: index == activeIndex,
            label: '${index + 1}번 페이지',
            child: onSelected == null
                ? Padding(
                    padding: EdgeInsets.symmetric(horizontal: dotSpacing),
                    child: _PageIndicatorDot(
                      size: dotSize,
                      color: index == activeIndex ? activeColor : inactiveColor,
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelected!(index),
                    child: SizedBox.square(
                      dimension: AppSizes.minimumTapTarget,
                      child: Center(
                        child: _PageIndicatorDot(
                          size: dotSize,
                          color: index == activeIndex
                              ? activeColor
                              : inactiveColor,
                        ),
                      ),
                    ),
                  ),
          ),
      ],
    ),
  );
}

class _PageIndicatorDot extends StatelessWidget {
  const _PageIndicatorDot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
