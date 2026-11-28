import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_icon_button.dart';
import '../../../../widgets/app_tap_slop.dart';
import '../../data/preference_history_content.dart';
import 'preference_history_calendar.dart';

/// Month header (previous, month selector, next) above the calendar grid.
class HistoryCalendarCard extends StatelessWidget {
  const HistoryCalendarCard({
    required this.displayedMonth,
    required this.days,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onChooseMonth,
    this.onSelectDay,
    super.key,
  });

  final DateTime displayedMonth;
  final List<HistoryDay> days;

  /// `null` at the earliest month and at this month, which disables the arrow.
  final VoidCallback? onPreviousMonth;
  final VoidCallback? onNextMonth;
  final VoidCallback onChooseMonth;
  final ValueChanged<DateTime>? onSelectDay;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 340;
          // A 32 circle in the middle of a 44 box that takes its taps. The
          // 6 the box has around the circle is taken off the row's inset,
          // so the circle's outer edge stays where the larger one's was.
          final inset = (compact ? 12.0 : 24.0) - _MonthArrow.slop;
          return Padding(
            padding: EdgeInsets.fromLTRB(inset, 14, inset, 14),
            child: Row(
              children: <Widget>[
                _MonthArrow(
                  icon: AppIconAsset.previous,
                  onPressed: onPreviousMonth,
                  tooltip: '이전 달 보기',
                ),
                Expanded(
                  child: Center(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const ValueKey<String>('history-month-selector'),
                        borderRadius: BorderRadius.circular(AppRadii.control),
                        onTap: onChooseMonth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: AppSpacing.sm,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                '${displayedMonth.year}년 '
                                '${displayedMonth.month}월',
                                textAlign: TextAlign.center,
                                textScaler: TextScaler.noScaling,
                                style: AppTextStyles.cardTitle,
                              ),
                              SizedBox(width: compact ? 2 : AppSpacing.xs),
                              AppIcon(
                                AppIconAsset.expand,
                                size: compact ? 11 : 14,
                                color: AppColors.textPrimary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _MonthArrow(
                  icon: AppIconAsset.next,
                  onPressed: onNextMonth,
                  tooltip: '다음 달 보기',
                ),
              ],
            ),
          );
        },
      ),
      const Divider(height: 1, color: AppColors.borderSubtle),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s14,
          AppSpacing.lg,
          AppSpacing.s14,
          AppSpacing.xl,
        ),
        child: HistoryCalendar(days: days, onSelectDay: onSelectDay),
      ),
    ],
  );
}

/// One of the two arrows beside the month: a small outlined circle that
/// takes a tap anywhere in the 44 box around it.
class _MonthArrow extends StatelessWidget {
  const _MonthArrow({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final AppIconAsset icon;
  final VoidCallback? onPressed;
  final String tooltip;

  /// What the circle lacks of a tap target on each side.
  static const slop = AppSpacing.s6;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: AppSizes.minimumTapTarget,
    child: Center(
      child: AppTapSlop(
        slop: const EdgeInsets.all(slop),
        child: AppIconButton(
          icon: icon,
          onPressed: onPressed,
          tooltip: tooltip,
          size: AppIconButtonSize.small,
          variant: AppIconButtonVariant.outline,
          tone: AppIconButtonTone.ink,
        ),
      ),
    ),
  );
}
