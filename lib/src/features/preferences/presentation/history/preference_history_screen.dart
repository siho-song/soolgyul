import 'package:flutter/material.dart';
import '../../../../design/app_feature_layouts.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_page_scroll_view.dart';
import '../../../../widgets/app_surface.dart';
import '../../data/preference_history_content.dart';
import 'history_calendar_card.dart';
import 'history_month_picker.dart';
import 'preference_history_daily_records.dart';
import 'preference_history_monthly_summary.dart';

class PreferenceHistoryScreen extends StatefulWidget {
  const PreferenceHistoryScreen({
    required this.gateway,
    required this.onOpenCard,
    this.today,
    super.key,
  });

  /// `null` (signed out, or no backend) shows every month empty.
  final PreferenceHistoryGateway? gateway;

  /// Opens the saved card with this result id.
  final ValueChanged<String> onOpenCard;

  /// Its month is the one shown first; the device's today when `null`.
  final DateTime? today;

  @override
  State<PreferenceHistoryScreen> createState() =>
      _PreferenceHistoryScreenState();
}

class _PreferenceHistoryScreenState extends State<PreferenceHistoryScreen> {
  late DateTime _displayedMonth;

  /// The day picked on the calendar; `null` lists the whole month.
  DateTime? _pickedDay;
  Future<List<HistoryRecord>>? _records;

  @override
  void initState() {
    super.initState();
    final now = widget.today ?? DateTime.now();
    _displayedMonth = DateTime(now.year, now.month);
    final gateway = widget.gateway;
    _records = gateway == null ? null : _openOnLatestMonth(gateway);
  }

  void _load() {
    _records = widget.gateway?.loadMonth(_displayedMonth);
  }

  /// The tab opens on the month of the newest record, so a reader back
  /// after a quiet spell meets their last cards instead of an empty grid.
  /// Without a record, or when the lookup fails, it stays on this month.
  Future<List<HistoryRecord>> _openOnLatestMonth(
    PreferenceHistoryGateway gateway,
  ) async {
    DateTime? latest;
    try {
      latest = await gateway.latestRecordedAt();
    } catch (_) {
      latest = null;
    }
    if (!mounted) return const <HistoryRecord>[];
    if (latest != null) {
      final month = DateTime(latest.year, latest.month);
      if (month != _displayedMonth) {
        setState(() => _displayedMonth = month);
      }
    }
    return gateway.loadMonth(_displayedMonth);
  }

  /// Shows [month]; [day] is picked in it when given.
  void _showMonth(DateTime month, {DateTime? day}) {
    setState(() {
      _displayedMonth = DateTime(month.year, month.month);
      _pickedDay = day;
      _load();
    });
  }

  /// A tap picks a day; a tap on the picked day goes back to the month.
  void _toggleDay(DateTime day) => setState(
    () => _pickedDay = _pickedDay != null && historySameDay(_pickedDay!, day)
        ? null
        : day,
  );

  Future<void> _chooseMonth() async {
    final pick = await showHistoryMonthPicker(
      context,
      _pickedDay ?? _displayedMonth,
    );
    if (pick == null || !mounted) return;
    _showMonth(pick.month, day: pick.day);
  }

  @override
  Widget build(BuildContext context) => AppPageScrollView(
    topPadding: 0,
    child: AppContentPadding(
      horizontalPadding: PreferenceLayoutSpacing.contentHorizontal,
      child: FutureBuilder<List<HistoryRecord>>(
        key: ValueKey<DateTime>(_displayedMonth),
        future: _records,
        builder: (context, snapshot) {
          final loading =
              _records != null &&
              snapshot.connectionState != ConnectionState.done;
          final records = snapshot.data ?? const <HistoryRecord>[];
          final day = _pickedDay;
          final shown = day == null
              ? records
              : <HistoryRecord>[
                  for (final record in records)
                    if (historySameDay(record.recordedAt, day)) record,
                ];
          final period = day == null
              ? '${_displayedMonth.month}월'
              : '${day.month}월 ${day.day}일';
          return AppSurface(
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
                    displayedMonth: _displayedMonth,
                    days: historyMonthDays(
                      _displayedMonth,
                      records,
                      selected: day,
                    ),
                    onPreviousMonth: () => _showMonth(
                      DateTime(_displayedMonth.year, _displayedMonth.month - 1),
                    ),
                    onNextMonth: () => _showMonth(
                      DateTime(_displayedMonth.year, _displayedMonth.month + 1),
                    ),
                    onChooseMonth: _chooseMonth,
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
                  else if (snapshot.hasError)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: _HistoryMessage(
                        text: '기록을 불러오지 못했어요.',
                        action: TextButton(
                          onPressed: () => setState(_load),
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
                        month: _displayedMonth,
                        records: records,
                        today: widget.today ?? DateTime.now(),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
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
