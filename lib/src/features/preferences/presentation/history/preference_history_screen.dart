import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/async_shown.dart';
import '../../../../design/app_feature_layouts.dart';
import '../../../../design/app_tokens.dart';
import '../../../../widgets/app_chip.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/main_tab_title.dart';
import '../../../../widgets/app_page_scroll_view.dart';
import '../../../../widgets/app_section_action.dart';
import '../../../../widgets/app_surface.dart';
import '../../data/preference_history_content.dart';
import '../../data/preference_history_providers.dart';
import 'history_calendar_card.dart';
import 'history_month_picker.dart';
import 'preference_history_daily_records.dart';
import '../../../../widgets/app_state_view.dart';

class PreferenceHistoryScreen extends ConsumerStatefulWidget {
  const PreferenceHistoryScreen({
    required this.onOpenCard,
    this.onOpenSearch,
    this.onRefresh,
    this.today,
    super.key,
  });

  /// Opens the saved card with this result id.
  final ValueChanged<String> onOpenCard;

  /// Opens 기록 검색; `null` leaves its chip out.
  final VoidCallback? onOpenSearch;

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
    // The month can change under a picked day (the newest record's month
    // after a new record); a day outside the month shown is let go.
    if (_pickedDay case final picked?
        when picked.year != displayedMonth.year ||
            picked.month != displayedMonth.month) {
      _pickedDay = null;
    }
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
    // A picked day shows the way back to the whole month in words; a tap
    // on the day itself does the same.
    Widget? wholeMonth({bool large = false}) => day == null
        ? null
        : AppSectionAction(
            key: const ValueKey<String>('history-whole-month'),
            label: '${displayedMonth.month}월 전체 보기',
            large: large,
            onPressed: () => setState(() => _pickedDay = null),
          );
    final onRefresh = widget.onRefresh;
    return AppPageScrollView(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The room above the title is the same as under it, so the
            // chip centred on this box is level with the title and has its
            // whole tap target inside the page.
            Stack(
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.lg),
                  child: MainTabTitle('기록'),
                ),
                if (widget.onOpenSearch case final onOpenSearch?)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AppChip(
                        key: const ValueKey<String>('history-search-chip'),
                        label: '기록 검색',
                        leadingIcon: AppIconAsset.search,
                        onPressed: onOpenSearch,
                      ),
                    ),
                  ),
              ],
            ),
            AppSurface(
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
                      onPreviousMonth: displayedMonth.isAfter(historyFirstMonth)
                          ? () => _showMonth(
                              DateTime(
                                displayedMonth.year,
                                displayedMonth.month - 1,
                              ),
                            )
                          : null,
                      onNextMonth: displayedMonth.isBefore(_thisMonth)
                          ? () => _showMonth(
                              DateTime(
                                displayedMonth.year,
                                displayedMonth.month + 1,
                              ),
                            )
                          : null,
                      onChooseMonth: () => _chooseMonth(displayedMonth),
                      onSelectDay: _toggleDay,
                    ),
                    const Divider(height: 1, color: AppColors.borderSubtle),
                    if (loading)
                      const AppLoadingView(
                        key: ValueKey<String>('history-loading'),
                      )
                    else if (failed)
                      AppErrorView(
                        title: '기록을 불러오지 못했어요',
                        error: monthRecords?.error,
                        onRetry: () => ref.invalidate(
                          historyMonthProvider(displayedMonth),
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
                            title: '$period의 기록',
                            titleAction: wholeMonth(),
                            records: shown,
                            onOpenCard: widget.onOpenCard,
                          ),
                        )
                      else
                        AppEmptyView(
                          icon: AppIconAsset.calendar,
                          message: '$period에는 남긴 기록이 없어요.',
                          action: wholeMonth(large: true),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
