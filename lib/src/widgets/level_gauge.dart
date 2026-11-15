import '../design/app_tokens.dart';
import 'package:flutter/material.dart';

import '../design/app_typography.dart';
import 'kept_text.dart';
import 'paper_box.dart';
import 'text_underline.dart';

/// One taste level as a five-segment bar between its two end words:
/// "당도 낮음 ■■□□□ 높음 1~2". The note stays on the bar's line (도수
/// 40~43% too) and shrinks to fit; only one beside a wide label (당도(주도))
/// moves under the bar.
///
/// [LevelGauge.worded] says the mark in a word after the bar instead of
/// the end words: "당도 ■□□□□ 드라이".
class LevelGauge extends StatelessWidget {
  const LevelGauge({
    required this.label,
    required this.mark,
    this.note,
    this.low = '낮음',
    this.high = '높음',
    this.onExplain,
    super.key,
  }) : word = null,
       _worded = false;

  /// The name, the bar, then [word] in ink and [note] in grey after it. A
  /// row of a worded box without a word of its own still lines up here.
  const LevelGauge.worded({
    required this.label,
    required this.mark,
    this.word,
    this.note,
    this.onExplain,
    super.key,
  }) : low = '',
       high = '',
       _worded = true;

  final String label;

  /// 1–5; anything outside is clamped.
  final int mark;

  /// The mark as a word: 드라이, 미디엄 바디.
  final String? word;
  final String? note;
  final String low;
  final String high;

  /// With it the label is underlined and a touch calls this with the
  /// label's own context, for an explanation to open against.
  final void Function(BuildContext label)? onExplain;
  final bool _worded;

  static const _name = AppTextStyle(
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
  static const _end = AppTextStyle(
    fontSize: 12,
    height: 1.4,
    color: PaperInk.grey,
  );

  static const double _lowWidth = 40;
  static const double _barWidth = 120;

  /// What a worded row keeps for its word before the bar gives way.
  static const double _wordRoom = 96;
  static const double _wordGap = 10;

  double get _labelWidth => label.length > 4 ? 80 : 52;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _worded
        ? _buildWorded(context, constraints.maxWidth)
        : _build(context, constraints.maxWidth),
  );

  Widget _build(BuildContext context, double maxWidth) {
    final note = this.note;
    final labelWidth = _labelWidth;
    final longNote = note != null && labelWidth > 52;
    // The bar is 120 wide and gives way only where the row would not fit
    // otherwise (a wide label on a narrow phone).
    final rest =
        labelWidth +
        _lowWidth +
        6 +
        _textWidth(context, high) +
        (note != null && !longNote ? 8 : 0);
    final barWidth = (maxWidth - rest).clamp(20.0, _barWidth);
    final gauge = Row(
      children: <Widget>[
        SizedBox(width: labelWidth, child: _labelText(context)),
        // A fixed slot so the bars line up whatever the end word's length.
        SizedBox(
          width: _lowWidth,
          child: Text(low, style: _end),
        ),
        SizedBox(width: barWidth, child: _bar()),
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
    return longNote ? _withNoteUnder(gauge, note, labelWidth) : gauge;
  }

  Widget _buildWorded(BuildContext context, double maxWidth) {
    final word = this.word;
    final note = this.note;
    final labelWidth = _labelWidth;
    final longNote = note != null && labelWidth > 52;
    final beside = longNote ? null : note;
    final room = MediaQuery.textScalerOf(context).scale(_wordRoom);
    // Every bar of a box is as wide, so the words start on one line.
    final barWidth = (maxWidth - labelWidth - _wordGap - room).clamp(
      20.0,
      _barWidth,
    );
    final gauge = Row(
      children: <Widget>[
        SizedBox(width: labelWidth, child: _labelText(context)),
        SizedBox(width: barWidth, child: _bar()),
        if (word != null || beside != null) ...<Widget>[
          const SizedBox(width: _wordGap),
          Expanded(
            child: KeptText.rich(
              TextSpan(
                children: <InlineSpan>[
                  if (word != null) TextSpan(text: word, style: _word),
                  if (word != null && beside != null)
                    const TextSpan(text: '  '),
                  if (beside != null) TextSpan(text: beside, style: _end),
                ],
              ),
            ),
          ),
        ],
      ],
    );
    return longNote ? _withNoteUnder(gauge, note, labelWidth) : gauge;
  }

  /// The name; with [onExplain] only its letters are underlined and open
  /// the explanation, not the whole slot.
  Widget _labelText(BuildContext context) {
    final text = Text(label, style: _name);
    final onExplain = this.onExplain;
    if (onExplain == null) return text;
    return Align(
      alignment: Alignment.centerLeft,
      child: Builder(
        builder: (labelContext) => GestureDetector(
          key: ValueKey<String>('level-gauge-explain-$label'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onExplain(labelContext),
          child: TextUnderline(
            color: PaperInk.inkSoft,
            fontSize: MediaQuery.textScalerOf(context).scale(13),
            child: text,
          ),
        ),
      ),
    );
  }

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

  static Widget _withNoteUnder(Widget gauge, String note, double labelWidth) =>
      Column(
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

  /// [text]'s width in the end words' style, rounded up.
  static double _textWidth(BuildContext context, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(_end),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }
}
