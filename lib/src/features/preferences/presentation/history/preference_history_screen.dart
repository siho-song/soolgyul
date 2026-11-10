import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/async_shown.dart';
import '../../../../design/app_feature_layouts.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_page_scroll_view.dart';
import '../../../../widgets/app_surface.dart';
import '../../data/preference_history_content.dart';
import '../../data/preference_history_providers.dart';
import 'history_calendar_card.dart';
import 'history_month_picker.dart';
import 'preference_history_daily_records.dart';
import 'preference_history_monthly_summary.dart';

class PreferenceHistoryScreen extends ConsumerStatefulWidget {
  const PreferenceHistoryScreen({
    required this.onOpenCard,
    this.onRefresh,
    this.today,
    super.key,
  });

  /// Opens the saved card with this result id.
  final ValueChanged<String> onOpenCard;

  /// Pulling the tab down runs this, then waits for the shown month: for a
  /// card saved on the web or another device.
  final Future<void> Function()? onRefresh;

  /// Its month is the one shown first; the device's today when `null`.
  final DateTime? today;

  @override
  ConsumerState<PreferenceHistoryScreen> createState() =>
      _PreferenceHistoryScreenState();
}

class _PreferenceHistoryScreenState
    extends ConsumerState<PreferenceHistoryScreen> {
  /// The month the reader moved to; `null` until they move.
  DateTime? _chosenMonth;

  /// The day picked on the calendar; `null` lists the whole month.
  DateTime? _pickedDay;

  DateTime get _thisMonth {
    final now = widget.today ?? DateTime.now();
    return DateTime(now.year, now.month);
  }

  /// The tab opens on the month of the newest record, so a reader back
  /// after a quiet spell meets their last cards instead of an empty grid.
  /// Without a record, or when the lookup fails, it stays on this month.
  /// `null` while the newest record is still being looked up.
  DateTime? _openingMonth() {
    final latest = ref.watch(historyLatestProvider);
    if (latest.hasError && !latest.isLoading) return _thisMonth;
    if (latest.isReloading || !latest.hasValue) return null;
    final newest = latest.value;
    return newest == null ? _thisMonth : DateTime(newest.year, newest.month);
  }

  /// Shows [month]; [day] is picked in it when given.
  void _showMonth(DateTime month, {DateTime? day}) {
    setState(() {
      _chosenMonth = DateTime(month.year, month.month);
      _pickedDay = day;
    });
  }

  /// A tap picks a day; a tap on the picked day goes back to the month.
  void _toggleDay(DateTime day) => setState(
    () => _pickedDay = _pickedDay != null && historySameDay(_pickedDay!, day)
        ? null
        : day,
  );

  Future<void> _chooseMonth(DateTime displayedMonth) async {
    final pick = await showHistoryMonthPicker(
      context,
      _pickedDay ?? displayedMonth,
    );
    if (pick == null || !mounted) return;
    _showMonth(pick.month, day: pick.day);
  }

  @override
  Widget build(BuildContext context) {
    final hasGateway = ref.watch(preferenceHistoryGatewayProvider) != null;
    final opening = hasGateway ? _openingMonth() : _thisMonth;
    final displayedMonth = _chosenMonth ?? opening ?? _thisMonth;
    final monthRecords = hasGateway && opening != null
        ? ref.watch(historyMonthProvider(displayedMonth))
        : null;
    final shownRecords = monthRecords == null ? null : shownValue(monthRecords);
    final loading =
        hasGateway &&
        (opening == null || (shownRecords == null && monthRecords!.isLoading));
    final failed =
        !loading && shownRecords == null && (monthRecords?.hasError ?? false);
    final records = shownRecords ?? const <HistoryRecord>[];
    final day = _pickedDay;
    final shown = day == null
        ? records
        : <HistoryRecord>[
            for (final record in records)
              if (historySameDay(record.recordedAt, day)) record,
          ];
    final period = day == null
        ? '${displayedMonth.month}월'
        : '${day.month}월 ${day.day}일';
    final onRefresh = widget.onRefresh;
    return AppPageScrollView(
      topPadding: 0,
      onRefresh: onRefresh == null || !hasGateway
          ? null
          : () async {
              await onRefresh();
              try {
                await ref.read(historyMonthProvider(displayedMonth).future);
              } catch (_) {
                // The month shows its own failure and retry.
              }
            },
      child: AppContentPadding(
        horizontalPadding: PreferenceLayoutSpacing.contentHorizontal,
        child: AppSurface(
          key: const ValueKey<String>('history-content-card'),
          variant: AppSurfaceVariant.card,
          borderRadius: AppRadii.card,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Column(
              key: const ValueKey<String>('history-content-column'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                HistoryCalendarCard(
                  key: const ValueKey<String>('history-calendar-content'),
                  displayedMonth: displayedMonth,
                  days: historyMonthDays(
                    displayedMonth,
                    records,
                    selected: day,
                  ),
                  onPreviousMonth: () => _showMonth(
                    DateTime(displayedMonth.year, displayedMonth.month - 1),
                  ),
                  onNextMonth: () => _showMonth(
                    DateTime(displayedMonth.year, displayedMonth.month + 1),
                  ),
                  onChooseMonth: () => _chooseMonth(displayedMonth),
                  onSelectDay: _toggleDay,
                ),
                const Divider(height: 1, color: AppColors.borderSubtle),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: Center(
                      child: CircularProgressIndicator(
                        key: ValueKey<String>('history-loading'),
                      ),
                    ),
                  )
                else if (failed)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: _HistoryMessage(
                      text: '기록을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
                      action: TextButton(
                        onPressed: () => ref.invalidate(
                          historyMonthProvider(displayedMonth),
                        ),
                        child: const Text('다시 시도'),
                      ),
                    ),
                  )
                else ...<Widget>[
                  if (shown.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.xxl,
                        AppSpacing.xl,
                        AppSpacing.xxl,
                      ),
                      child: HistoryDayCard(
                        key: ValueKey<String>('history-list-$period'),
                        title: '$period의 술결',
                        records: shown,
                        onOpenCard: widget.onOpenCard,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: _HistoryMessage(text: '$period에는 기록된 술결이 없어요.'),
                    ),
                  if (records.isNotEmpty) ...<Widget>[
                    const Divider(height: 1, color: AppColors.borderSubtle),
                    HistoryMonthSummaryCard(
                      month: displayedMonth,
                      records: records,
                      today: widget.today ?? DateTime.now(),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => AppPanel(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.xl,
    ),
    child: Column(
      children: <Widget>[
        const AppIcon(
          AppIconAsset.calendar,
          size: 25,
          color: AppColors.textTertiary,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          text,
          textAlign: TextAlign.center,
          style: AppTextStyles.historyEmptyState,
        ),
        ?action,
      ],
    ),
  );
}
