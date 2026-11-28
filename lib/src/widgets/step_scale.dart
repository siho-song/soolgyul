import 'package:flutter/material.dart';

import '../core/sensory/sensory_gauges.dart';
import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'kept_text.dart';
import 'level_gauge.dart';

/// A five-step bar as the questionnaire's gauges draw it, and the words
/// under it: the low end, 보통 at the middle, the high end. The question
/// chooses on it; the tasting note shows what was chosen.

/// The word under the middle step.
const _middleWord = '보통';

/// The words under the bar's two ends, which say the way it runs.
final _endStyle = AppTextStyles.labelSmall.copyWith(
  fontWeight: FontWeight.w500,
  color: AppColors.textTertiary,
);

/// How thick the bar is drawn.
const _barHeight = 6.0;

/// The tick between two steps, across and how far it reaches past the bar.
const _tickWidth = 1.5;
const _tickReach = 3.0;

/// The height the bar's line is drawn in, above the words.
const stepBarLineHeight = 22.0;

/// The bar alone, at [stepBarLineHeight], with [level] filled; none while
/// it is null.
class StepBar extends StatelessWidget {
  const StepBar({required this.level, super.key});

  final int? level;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: stepBarLineHeight,
    child: CustomPaint(painter: _StepBarPainter(level: level)),
  );
}

/// The words under the bar, kept inside its width: [low] from the bar's
/// left end, 보통 at its middle, [high] to its right end, each in a third
/// of the bar. A long word wraps, at a space or after a ·, to a second
/// line; it is never cut inside a word or drawn past the bar.
class StepEndWords extends StatelessWidget {
  const StepEndWords({required this.low, required this.high, super.key});

  final String low;
  final String high;

  /// A line may break after a · as at a space (드라이·/미네랄).
  static String _breakable(String word) => word.replaceAll('·', '·\u200B');

  @override
  Widget build(BuildContext context) {
    Widget word(String text, TextAlign align) => Expanded(
      child: KeptText(
        _breakable(text),
        maxLines: 2,
        textAlign: align,
        style: _endStyle,
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        word(low, TextAlign.left),
        word(_middleWord, TextAlign.center),
        word(high, TextAlign.right),
      ],
    );
  }
}

/// A bar that is only read: [level] filled and, with [ends], their words
/// under it.
class StepScale extends StatelessWidget {
  const StepScale({required this.level, this.ends, super.key});

  final int? level;
  final (String low, String high)? ends;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StepBar(level: level),
      if (ends case (final low, final high)) StepEndWords(low: low, high: high),
    ],
  );
}

/// One gauge that is only read: its name, the step filled on its bar, and
/// the words under the bar's ends.
typedef StepGaugeRow = ({String label, int level, (String, String)? ends});

/// Gauges that are only read, one a row: the gauge's name, then the
/// questionnaire's five-step bar with its step filled and, under it, its
/// low end, 보통 and its high end. The tasting note lists the steps a reader
/// chose this way, and a drink's page the bottle's own levels, so a level
/// reads the same on both.
class StepGaugeRows extends StatelessWidget {
  const StepGaugeRows({required this.rows, required this.keyPrefix, super.key});

  final List<StepGaugeRow> rows;

  /// What each row's bar is keyed by before its gauge's name.
  final String keyPrefix;

  static const _nameWidth = 52.0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (final (index, row) in rows.indexed)
        Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: stepBarLineHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: _nameWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: Text(row.label, style: LevelGauge.nameStyle),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: StepScale(
                  key: ValueKey<String>('$keyPrefix${row.label}'),
                  level: row.level,
                  ends: row.ends,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// A pale rounded track, a tick between each two steps, and the chosen step
/// filled in the brand colour.
class _StepBarPainter extends CustomPainter {
  const _StepBarPainter({required this.level});

  final int? level;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / SensoryGauge.steps;
    final top = (size.height - _barHeight) / 2;
    const radius = Radius.circular(_barHeight / 2);
    canvas.drawRRect(
      RRect.fromLTRBR(0, top, size.width, top + _barHeight, radius),
      Paint()..color = AppColors.borderSubtle,
    );
    final tick = Paint()
      ..color = AppColors.borderStrong
      ..strokeWidth = _tickWidth;
    for (var step = 1; step < SensoryGauge.steps; step++) {
      final x = step * cell;
      canvas.drawLine(
        Offset(x, top - _tickReach),
        Offset(x, top + _barHeight + _tickReach),
        tick,
      );
    }
    if (level case final chosen?) {
      final left = (chosen - 1) * cell;
      canvas.drawRRect(
        RRect.fromLTRBR(left, top, left + cell, top + _barHeight, radius),
        Paint()..color = AppColors.gaugeChosen,
      );
    }
  }

  @override
  bool shouldRepaint(_StepBarPainter old) => old.level != level;
}
