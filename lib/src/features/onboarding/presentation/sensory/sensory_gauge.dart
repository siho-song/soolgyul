import 'package:flutter/material.dart';

import '../../../../core/sensory/sensory_gauges.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';

/// What a gauge's row says until a step is chosen.
const _unchosen = '선택해 주세요';

final _unchosenStyle = AppTextStyles.labelSmall.copyWith(
  fontWeight: FontWeight.w500,
  color: AppColors.textTertiary,
);
final _termStyle = AppTextStyles.labelSmall.copyWith(
  color: AppColors.actionPrimary,
);
final _hintStyle = AppTextStyles.labelSmall.copyWith(
  fontWeight: FontWeight.w500,
  color: AppColors.textSecondary,
);

/// The words under the two ends of a track, which say the way it runs.
final _endStyle = AppTextStyles.labelSmall.copyWith(
  fontWeight: FontWeight.w500,
  color: AppColors.textTertiary,
);

/// What a screen reader says of a gauge with no step chosen.
const _noneChosen = '선택 안 함';

/// The knob on the chosen stop, across.
const _knobSize = 24.0;

/// The white mark at the knob's middle, across.
const _knobGripSize = 8.0;

/// A stop's hollow circle, across.
const _stopSize = 10.0;

/// How thick the track and the edge of a stop are drawn.
const _trackStroke = 2.0;

/// The gauges of a page, one row each, in the order the kind is asked them.
class SensoryGaugeList extends StatelessWidget {
  const SensoryGaugeList({
    required this.gauges,
    required this.levelOf,
    required this.onChoose,
    super.key,
  });

  final List<SensoryGauge> gauges;

  /// The step chosen on an axis; null while none is.
  final int? Function(String axis) levelOf;

  /// A step of an axis chosen by a tap or a drag.
  final void Function(String axis, int level) onChoose;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, gauge) in gauges.indexed)
        Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.xl),
          child: SensoryGaugeRow(
            gauge: gauge,
            level: levelOf(gauge.axis),
            onChoose: (level) => onChoose(gauge.axis, level),
          ),
        ),
    ],
  );
}

/// One gauge: the axis's name at the left, at the right what the chosen step
/// is called (선택해 주세요 until one is), and under them a thin track of five
/// hollow stops with the knob on the chosen one. A tap on a stop puts the
/// knob there and a tap on the knob's own stop clears the gauge; a drag
/// along the track moves the knob from stop to stop. Under the track's ends
/// are the words of its first and last steps. A gauge may be left with
/// nothing chosen.
class SensoryGaugeRow extends StatefulWidget {
  const SensoryGaugeRow({
    required this.gauge,
    required this.level,
    required this.onChoose,
    super.key,
  });

  final SensoryGauge gauge;

  /// The step chosen, 1 to 5; null while none is.
  final int? level;

  /// A stop chosen by a tap or a drag. The owner clears the gauge when it
  /// is the chosen one.
  final ValueChanged<int> onChoose;

  @override
  State<SensoryGaugeRow> createState() => _SensoryGaugeRowState();
}

class _SensoryGaugeRowState extends State<SensoryGaugeRow> {
  SensoryGauge get _gauge => widget.gauge;

  /// The stop the drag under way last chose. A drag hands each stop to the
  /// owner once, since a stop handed over twice would be cleared.
  int? _dragged;

  void _dragTo(int step) {
    if (step == _dragged) return;
    _dragged = step;
    widget.onChoose(step);
  }

  Widget _chosenLabel() {
    final level = widget.level;
    if (level == null) return Text(_unchosen, style: _unchosenStyle);
    final chosen = _gauge.levelAt(level);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: chosen.term, style: _termStyle),
          if (chosen.hint case final hint?)
            TextSpan(text: ' · $hint', style: _hintStyle),
        ],
      ),
      maxLines: 1,
    );
  }

  /// The track: its line and stops, a column to tap around each stop, and
  /// the knob over the chosen one. The first and last stops stand half a
  /// knob in from the ends, so the knob stays inside the row.
  Widget _track(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final gap = (width - _knobSize) / (SensoryGauge.steps - 1);
      double centre(int step) => _knobSize / 2 + (step - 1) * gap;
      int stepAt(double x) =>
          ((x - _knobSize / 2) / gap).round().clamp(0, SensoryGauge.steps - 1) +
          1;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        // Sideways only, so the page under it still scrolls up and down.
        onHorizontalDragStart: (details) {
          _dragged = widget.level;
          _dragTo(stepAt(details.localPosition.dx));
        },
        onHorizontalDragUpdate: (details) =>
            _dragTo(stepAt(details.localPosition.dx)),
        child: SizedBox(
          height: AppSizes.minimumTapTarget,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _TrackPainter(gap: gap)),
              ),
              for (var step = 1; step <= SensoryGauge.steps; step++)
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: step == 1 ? 0 : centre(step) - gap / 2,
                  right: step == SensoryGauge.steps
                      ? 0
                      : width - centre(step) - gap / 2,
                  child: GestureDetector(
                    key: ValueKey('gauge:${_gauge.axis}:$step'),
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: () => widget.onChoose(step),
                  ),
                ),
              if (widget.level case final level?)
                AnimatedPositioned(
                  key: ValueKey('gauge-knob:${_gauge.axis}'),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : AppDurations.standard,
                  curve: Curves.easeOut,
                  left: centre(level) - _knobSize / 2,
                  top: (AppSizes.minimumTapTarget - _knobSize) / 2,
                  width: _knobSize,
                  height: _knobSize,
                  // The column under the knob takes the tap.
                  child: const IgnorePointer(child: _Knob()),
                ),
            ],
          ),
        ),
      );
    },
  );

  /// The words under the track's ends: those of the two characters it runs
  /// between, or of its first and last steps.
  Widget _ends() {
    final (low, high) =
        _gauge.ends ??
        (_gauge.levelAt(1).term, _gauge.levelAt(SensoryGauge.steps).term);
    Widget end(String word, TextAlign align) => Expanded(
      child: Text(
        word,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: _endStyle,
      ),
    );
    return Row(
      children: [
        end(low, TextAlign.start),
        const SizedBox(width: AppSpacing.md),
        end(high, TextAlign.end),
      ],
    );
  }

  String _valueAt(int? level) =>
      level == null ? _noneChosen : _gauge.levelAt(level).term;

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(_gauge.label, style: AppTextStyles.onboardingOptionLabel),
            const SizedBox(width: AppSpacing.md),
            // A long label shrinks to stay on the name's line, so choosing a
            // step never moves the track.
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: FittedBox(
                  key: ValueKey('gauge-label:${_gauge.axis}'),
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _chosenLabel(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        // A slider to a screen reader: a step up from nothing chosen is the
        // first stop, and a step down from the first stop clears it.
        Semantics(
          container: true,
          slider: true,
          label: _gauge.label,
          value: _valueAt(level),
          increasedValue: level == SensoryGauge.steps
              ? null
              : _valueAt((level ?? 0) + 1),
          decreasedValue: level == null
              ? null
              : _valueAt(level == 1 ? null : level - 1),
          onIncrease: level == SensoryGauge.steps
              ? null
              : () => widget.onChoose((level ?? 0) + 1),
          onDecrease: level == null
              ? null
              : () => widget.onChoose(level == 1 ? 1 : level - 1),
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_track(context), _ends()],
          ),
        ),
      ],
    );
  }
}

/// The line of a gauge and its five hollow stops, [gap] apart. The line is
/// drawn between the stops and not through them, so a stop shows whatever
/// the gauge stands on.
class _TrackPainter extends CustomPainter {
  const _TrackPainter({required this.gap});

  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.borderStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = _trackStroke;
    final y = size.height / 2;
    const radius = (_stopSize - _trackStroke) / 2;
    const edge = _stopSize / 2;
    for (var index = 0; index < SensoryGauge.steps; index++) {
      final x = _knobSize / 2 + index * gap;
      canvas.drawCircle(Offset(x, y), radius, paint);
      if (index > 0) {
        canvas.drawLine(Offset(x - gap + edge, y), Offset(x - edge, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.gap != gap;
}

/// The knob on the chosen stop: a round of the brand colour with a small
/// white mark at its middle and a soft shadow under it.
class _Knob extends StatelessWidget {
  const _Knob();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.actionPrimary,
      shape: BoxShape.circle,
      boxShadow: AppShadows.floatingControl,
    ),
    child: Center(
      child: SizedBox.square(
        dimension: _knobGripSize,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.textOnPrimary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    ),
  );
}
