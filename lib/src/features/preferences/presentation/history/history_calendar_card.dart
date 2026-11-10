import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_icon_button.dart';
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
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onChooseMonth;
  final ValueChanged<DateTime>? onSelectDay;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 340;
          const controlSize = AppIconButtonSize.compact;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 24,
              14,
              compact ? 12 : 24,
              14,
            ),
            child: Row(
              children: <Widget>[
                AppIconButton(
                  icon: AppIconAsset.previous,
                  onPressed: onPreviousMonth,
                  tooltip: '이전 달 보기',
                  size: controlSize,
                  variant: AppIconButtonVariant.outline,
                  tone: AppIconButtonTone.ink,
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
                                style: AppTextStyles.historyMonthTitle,
                              ),
                              SizedBox(width: compact ? 2 : AppSpacing.xs),
                              AppIcon(
                                AppIconAsset.expand,
                                size: compact ? 11 : 14,
                                color: AppColors.textPrimary,
                                weight: AppIconWeight.strong,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                AppIconButton(
                  icon: AppIconAsset.next,
                  onPressed: onNextMonth,
                  tooltip: '다음 달 보기',
                  size: controlSize,
                  variant: AppIconButtonVariant.outline,
                  tone: AppIconButtonTone.ink,
                ),
              ],
            ),
          );
        },
      ),
      const Divider(height: 1, color: AppColors.borderSubtle),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
        child: HistoryCalendar(days: days, onSelectDay: onSelectDay),
      ),
    ],
  );
}
