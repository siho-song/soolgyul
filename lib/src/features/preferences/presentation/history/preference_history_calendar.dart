import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../data/preference_history_content.dart';

class HistoryCalendar extends StatelessWidget {
  const HistoryCalendar({super.key, required this.days, this.onSelectDay});

  final List<HistoryDay> days;

  /// Called with the tapped day of the shown month.
  final ValueChanged<DateTime>? onSelectDay;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: const <Widget>[
              _WeekLabel('일', color: Color(0xFFE00000)),
              _WeekLabel('월'),
              _WeekLabel('화'),
              _WeekLabel('수'),
              _WeekLabel('목'),
              _WeekLabel('금'),
              _WeekLabel('토', color: Color(0xFF54718C)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          clipBehavior: Clip.antiAlias,
          child: GridView.builder(
            key: const ValueKey<String>('history-calendar-grid'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final cell = days[index];
              final date = cell.date;
              final select = onSelectDay;
              return Container(
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: AppColors.borderSubtle),
                    bottom: BorderSide(color: AppColors.borderSubtle),
                  ),
                ),
                child: date == null || select == null
                    ? Center(
                        child: _HistoryDayMarker(day: cell, cellIndex: index),
                      )
                    : Semantics(
                        button: true,
                        selected: cell.selected,
                        label: '${date.month}월 ${date.day}일',
                        child: InkWell(
                          key: ValueKey<String>('history-day-${date.day}'),
                          onTap: () => select(date),
                          child: Center(
                            child: _HistoryDayMarker(
                              day: cell,
                              cellIndex: index,
                            ),
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _HistoryCalendarLegend(),
      ],
    );
  }
}

class _HistoryCalendarLegend extends StatelessWidget {
  const _HistoryCalendarLegend();

  static const _items = <(String, Color)>[
    ('와인', AppDataColors.wine),
    ('위스키', AppDataColors.whisky),
    ('사케', AppDataColors.sake),
    ('전통주', AppDataColors.traditional),
  ];

  @override
  Widget build(BuildContext context) => Semantics(
    label: '주종 색상 구분 범례',
    child: Wrap(
      key: const ValueKey<String>('history-calendar-legend'),
      alignment: WrapAlignment.center,
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final item in _items)
          _HistoryLegendItem(label: item.$1, color: item.$2),
      ],
    ),
  );
}

class _HistoryLegendItem extends StatelessWidget {
  const _HistoryLegendItem({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _HistoryWaveMark(color: color, width: 22),
      const SizedBox(width: AppSpacing.xs),
      Text(
        label,
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          fontSize: 12,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    ],
  );
}

class _WeekLabel extends StatelessWidget {
  const _WeekLabel(this.text, {this.color = AppColors.textPrimary});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Text(
      text,
      textAlign: TextAlign.center,
      textScaler: TextScaler.noScaling,
      style: AppTextStyles.sectionTitleSm.copyWith(color: color),
    ),
  );
}

class _HistoryDayMarker extends StatelessWidget {
  const _HistoryDayMarker({required this.day, required this.cellIndex});

  final HistoryDay day;
  final int cellIndex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compactDay = constraints.maxWidth < 42;
      final selectedWidth = (constraints.maxWidth - 6).clamp(30.0, 42.0);
      final selectedHeight = (constraints.maxHeight - 6).clamp(30.0, 44.0);
      return SizedBox.expand(
        key: ValueKey<String>('history-day-marker-$cellIndex'),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (day.selected)
              Container(
                key: const ValueKey<String>('history-selected-day'),
                width: selectedWidth,
                height: selectedHeight,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8ED),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(
                    color: const Color(0xFFE8BA72),
                    width: 1.4,
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x24D59A42),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  day.text,
                  textScaler: TextScaler.noScaling,
                  style: AppTextStyles.historyCalendarDay(
                    compact: compactDay,
                    selected: day.selected,
                    muted: day.muted,
                  ),
                ),
                if (day.rings.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxs),
                  _HistoryWaveRow(
                    colors: day.rings,
                    availableWidth: constraints.maxWidth - 6,
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _HistoryWaveRow extends StatelessWidget {
  const _HistoryWaveRow({required this.colors, required this.availableWidth});

  final List<Color> colors;
  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    final visibleColors = colors.take(3).toList(growable: false);
    final hiddenCount = colors.length - visibleColors.length;
    final waveWidth = hiddenCount > 0
        ? (availableWidth - 12).clamp(12.0, 19.0)
        : availableWidth.clamp(14.0, 19.0);
    final waveStackHeight = visibleColors.length * 3.5;
    return SizedBox(
      key: const ValueKey<String>('history-day-waves'),
      width: availableWidth,
      height: waveStackHeight,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final color in visibleColors)
                Padding(
                  padding: const EdgeInsets.only(bottom: .5),
                  child: _HistoryWaveMark(color: color, width: waveWidth),
                ),
            ],
          ),
          if (hiddenCount > 0) ...<Widget>[
            Positioned(
              right: 0,
              bottom: 0,
              child: Text(
                '+$hiddenCount',
                textScaler: TextScaler.noScaling,
                style: AppTextStyles.historyCalendarOverflow,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryWaveMark extends StatelessWidget {
  const _HistoryWaveMark({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey<String>('history-single-wave'),
    width: width,
    height: 3,
    child: CustomPaint(painter: _HistorySingleWavePainter(color)),
  );
}

class _HistorySingleWavePainter extends CustomPainter {
  const _HistorySingleWavePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(0, size.height / 2);
    final quarter = size.width / 8;
    for (var index = 0; index < 2; index++) {
      final start = index * size.width / 2;
      path
        ..quadraticBezierTo(
          start + quarter,
          0,
          start + quarter * 2,
          size.height / 2,
        )
        ..quadraticBezierTo(
          start + quarter * 3,
          size.height,
          start + quarter * 4,
          size.height / 2,
        );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HistorySingleWavePainter oldDelegate) =>
      oldDelegate.color != color;
}
