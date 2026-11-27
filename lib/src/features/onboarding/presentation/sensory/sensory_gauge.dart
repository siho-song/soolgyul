import 'package:flutter/material.dart';

import '../../../../core/sensory/sensory_gauges.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/step_scale.dart';

/// What a screen reader says of a gauge with no step chosen.
const _noneChosen = '선택 안 함';

/// The width the axis's name takes at the bar's left, the same on every
/// row so the bars line up.
const _nameWidth = 52.0;

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

/// One gauge: the axis's name at the left and, at its right, a bar of five
/// steps with a tick between each two and the chosen step filled. Under the
/// bar stand the words of its two ends and 보통 at the middle. A tap on a
/// step chooses it; a drag along the bar moves the choice from step to step.
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

  /// A step chosen by a tap or a drag.
  final ValueChanged<int> onChoose;

  @override
  State<SensoryGaugeRow> createState() => _SensoryGaugeRowState();
}

class _SensoryGaugeRowState extends State<SensoryGaugeRow> {
  SensoryGauge get _gauge => widget.gauge;

  /// The step the drag under way last chose, so each is handed over once.
  int? _dragged;

  void _dragTo(int step) {
    if (step == _dragged) return;
    _dragged = step;
    widget.onChoose(step);
  }

  /// The bar and the words under it: five equal steps, each a column to
  /// tap from the bar down through its word, the chosen one filled.
  Widget _bar() => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final cell = width / SensoryGauge.steps;
      int stepAt(double x) =>
          (x / cell).floor().clamp(0, SensoryGauge.steps - 1) + 1;
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.minimumTapTarget,
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StepBar(level: widget.level),
                  _words(),
                ],
              ),
              for (var step = 1; step <= SensoryGauge.steps; step++)
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: (step - 1) * cell,
                  width: cell,
                  child: GestureDetector(
                    key: ValueKey('gauge:${_gauge.axis}:$step'),
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: () => widget.onChoose(step),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  /// The words under the bar: its two ends under the first and last steps,
  /// 보통 under the middle one.
  Widget _words() {
    final (low, high) =
        _gauge.ends ??
        (_gauge.levelAt(1).term, _gauge.levelAt(SensoryGauge.steps).term);
    return StepEndWords(low: low, high: high);
  }

  String _valueAt(int? level) =>
      level == null ? _noneChosen : _gauge.levelAt(level).term;

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    // The name stands at the middle of the bar and its words.
    return Row(
      children: [
        SizedBox(
          width: _nameWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _gauge.label,
              key: ValueKey('gauge-name:${_gauge.axis}'),
              style: AppTextStyles.onboardingOptionLabel,
            ),
          ),
        ),
        Expanded(
          child: Semantics(
            container: true,
            slider: true,
            label: _gauge.label,
            value: _valueAt(level),
            increasedValue: level == SensoryGauge.steps
                ? null
                : _valueAt((level ?? 0) + 1),
            decreasedValue: level == null || level == 1
                ? null
                : _valueAt(level - 1),
            onIncrease: level == SensoryGauge.steps
                ? null
                : () => widget.onChoose((level ?? 0) + 1),
            onDecrease: level == null || level == 1
                ? null
                : () => widget.onChoose(level - 1),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_bar()],
            ),
          ),
        ),
      ],
    );
  }
}
