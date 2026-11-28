import '../design/app_tokens.dart';
import 'package:flutter/material.dart';

import '../design/app_typography.dart';
import 'kept_text.dart';
import 'paper_box.dart';

/// One taste level as its name, a five-segment bar and the mark said in a
/// word: "당도 ■□□□□ 드라이".
class LevelGauge extends StatelessWidget {
  const LevelGauge.worded({
    required this.label,
    required this.mark,
    this.word,
    super.key,
  });

  final String label;

  /// 1–5; anything outside is clamped.
  final int mark;

  /// The mark as a word: 드라이, 미디엄 바디. A row without one still lines
  /// up with the rows that have it.
  final String? word;

  /// The name's style, for a row that stands among gauges with no bar of
  /// its own.
  static const nameStyle = AppTextStyle(
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: PaperInk.inkSoft,
  );
  static const _word = AppTextStyle(
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w700,
    color: PaperInk.ink,
  );

  static const double _barWidth = 120;

  /// What a row keeps for its word before the bar gives way.
  static const double _wordRoom = 96;
  static const double _wordGap = 10;

  /// The room a row keeps for [label] before its bar: what is drawn under
  /// a gauge, or in a row without one, starts after it to line up with the
  /// bars.
  static double labelWidthOf(String label) => label.length > 4 ? 80 : 52;

  double get _labelWidth => labelWidthOf(label);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final word = this.word;
      final labelWidth = _labelWidth;
      final room = MediaQuery.textScalerOf(context).scale(_wordRoom);
      // Every bar of a box is as wide, so the words start on one line.
      final barWidth = (constraints.maxWidth - labelWidth - _wordGap - room)
          .clamp(20.0, _barWidth);
      return Row(
        children: <Widget>[
          SizedBox(
            width: labelWidth,
            child: Text(label, style: nameStyle),
          ),
          SizedBox(width: barWidth, child: _bar()),
          if (word != null) ...<Widget>[
            const SizedBox(width: _wordGap),
            Expanded(child: KeptText(word, style: _word)),
          ],
        ],
      );
    },
  );

  Widget _bar() => Row(
    children: <Widget>[
      for (var step = 1; step <= 5; step += 1) ...<Widget>[
        if (step > 1) const SizedBox(width: 3),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: step <= mark.clamp(0, 5) ? PaperInk.gauge : PaperInk.line,
              borderRadius: BorderRadius.circular(AppRadii.xs),
            ),
          ),
        ),
      ],
    ],
  );
}
