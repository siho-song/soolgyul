import '../design/app_tokens.dart';
import 'package:flutter/material.dart';

import '../design/app_typography.dart';
import 'paper_box.dart';

/// One taste level as a five-segment bar between its two end words:
/// "당도 낮음 ■■□□□ 높음 1~2". The note stays on the bar's line (도수
/// 40~43% too) and shrinks to fit; only one beside a wide label (당도(주도))
/// moves under the bar.
class LevelGauge extends StatelessWidget {
  const LevelGauge({
    required this.label,
    required this.mark,
    this.note,
    this.low = '낮음',
    this.high = '높음',
    super.key,
  });

  final String label;

  /// 1–5; anything outside is clamped.
  final int mark;
  final String? note;
  final String low;
  final String high;

  static const _end = AppTextStyle(
    fontSize: 11,
    height: 1.4,
    color: PaperInk.grey,
  );

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    final labelWidth = label.length > 4 ? 80.0 : 52.0;
    final longNote = note != null && labelWidth > 52;
    final gauge = Row(
      children: <Widget>[
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: const AppTextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: PaperInk.inkSoft,
            ),
          ),
        ),
        // A fixed slot so the bars line up whatever the end word's length.
        SizedBox(width: 40, child: Text(low, style: _end)),
        SizedBox(
          width: 120,
          child: Row(
            children: <Widget>[
              for (var step = 1; step <= 5; step += 1) ...<Widget>[
                if (step > 1) const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: step <= mark.clamp(0, 5)
                          ? PaperInk.gauge
                          : PaperInk.line,
                      borderRadius: BorderRadius.circular(AppRadii.xs),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(high, style: _end),
        if (note != null && !longNote) ...<Widget>[
          const SizedBox(width: 8),
          // The note takes what is left and shrinks rather than overflow.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(note, style: _end, maxLines: 1),
            ),
          ),
        ],
      ],
    );
    if (!longNote) return gauge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        gauge,
        const SizedBox(height: 3),
        Padding(
          padding: EdgeInsets.only(left: labelWidth),
          child: Text(note, style: _end),
        ),
      ],
    );
  }
}
