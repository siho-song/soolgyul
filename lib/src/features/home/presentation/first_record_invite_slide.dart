import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/kept_text.dart';

/// One slide of the first-record invite: a picture, the three things read
/// from it, and what that gives the member.
@immutable
class FirstRecordInviteSlide {
  const FirstRecordInviteSlide({
    required this.picture,
    required this.rows,
    required this.headline,
    required this.description,
    this.scanned = false,
  });

  final String picture;

  /// Whether the picture is a bottle in a camera's corner brackets, read by
  /// a scan line before the rows come.
  final bool scanned;

  final List<({String label, String value})> rows;
  final String headline;
  final String description;
}

/// When each part of a slide comes in, counted from the slide's start: the
/// picture, the scan line when the slide has one, then the rows one after
/// another, each with its check after it has landed.
class FirstRecordInviteTimeline {
  FirstRecordInviteTimeline(FirstRecordInviteSlide slide)
    : rowsStart = slide.scanned ? pictureFade + scan : pictureFade,
      _rows = slide.rows.length;

  static const pictureFade = AppDurations.slow;
  static final scan = AppDurations.slow * 2.5;
  static const rowEvery = AppDurations.slow;
  static const rowLands = AppDurations.standard;
  static const checkPops = AppDurations.standard;

  final Duration rowsStart;
  final int _rows;

  Duration rowStart(int index) => rowsStart + rowEvery * index;

  Duration get total => rowStart(_rows - 1) + rowLands + checkPops;

  /// The part of the whole between [from] and [from] + [length].
  Interval part(Duration from, Duration length, {Curve curve = Curves.linear}) {
    final whole = total.inMicroseconds;
    return Interval(
      from.inMicroseconds / whole,
      (from + length).inMicroseconds / whole,
      curve: curve,
    );
  }
}

/// A slide and its sequence. The sequence plays from its start each time
/// [run] changes and tells [onDone] when it has ended; with [still] the
/// slide shows its end at once and tells nothing.
class FirstRecordInviteSlideView extends StatefulWidget {
  const FirstRecordInviteSlideView({
    required this.index,
    required this.slide,
    required this.run,
    required this.still,
    required this.pictureWidth,
    required this.onDone,
    super.key,
  });

  final int index;
  final FirstRecordInviteSlide slide;
  final int run;
  final bool still;
  final double pictureWidth;
  final VoidCallback onDone;

  @override
  State<FirstRecordInviteSlideView> createState() =>
      _FirstRecordInviteSlideViewState();
}

class _FirstRecordInviteSlideViewState extends State<FirstRecordInviteSlideView>
    with SingleTickerProviderStateMixin {
  late final _timeline = FirstRecordInviteTimeline(widget.slide);
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: _timeline.total,
  )..addStatusListener(_revealChanged);

  late final _picture = _during(
    Duration.zero,
    FirstRecordInviteTimeline.pictureFade,
    Curves.easeOut,
  );
  late final _scan = _during(
    FirstRecordInviteTimeline.pictureFade,
    FirstRecordInviteTimeline.scan,
    Curves.easeInOut,
  );
  late final _rowLands = <Animation<double>>[
    for (var row = 0; row < widget.slide.rows.length; row++)
      _during(
        _timeline.rowStart(row),
        FirstRecordInviteTimeline.rowLands,
        Curves.easeOut,
      ),
  ];
  late final _checkPops = <Animation<double>>[
    for (var row = 0; row < widget.slide.rows.length; row++)
      _during(
        _timeline.rowStart(row) + FirstRecordInviteTimeline.rowLands,
        FirstRecordInviteTimeline.checkPops,
        Curves.easeOutBack,
      ),
  ];

  /// From 0 to 1 over the [length] of the sequence that starts at [from].
  Animation<double> _during(Duration from, Duration length, Curve curve) =>
      _reveal.drive(
        CurveTween(curve: _timeline.part(from, length, curve: curve)),
      );

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _reveal.value = 1;
    } else if (widget.run > 0) {
      _reveal.forward();
    }
  }

  @override
  void didUpdateWidget(FirstRecordInviteSlideView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.still) {
      if (_reveal.value != 1) _reveal.value = 1;
    } else if (widget.run != oldWidget.run) {
      _reveal.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  void _revealChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && !widget.still) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slide;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: FadeTransition(
            key: ValueKey<String>(
              'first-record-invite-picture-${widget.index}',
            ),
            opacity: _picture,
            child: _Picture(
              slide: slide,
              width: widget.pictureWidth,
              scan: _scan,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (var row = 0; row < slide.rows.length; row++) ...<Widget>[
          if (row > 0) const SizedBox(height: AppSpacing.sm),
          _Row(
            key: ValueKey<String>(
              'first-record-invite-row-${widget.index}-$row',
            ),
            label: slide.rows[row].label,
            value: slide.rows[row].value,
            lands: _rowLands[row],
            checkPops: _checkPops[row],
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        // One line on every phone: a narrow one draws it smaller.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            slide.headline,
            maxLines: 1,
            style: AppTextStyles.sectionTitle,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        KeptText(
          slide.description,
          textAlign: TextAlign.center,
          style: AppTextStyles.detail,
        ),
      ],
    );
  }
}

/// The slide's picture in its rounded box: the card's paper filling it, or
/// the bottle inside the camera's corner brackets.
class _Picture extends StatelessWidget {
  const _Picture({
    required this.slide,
    required this.width,
    required this.scan,
  });

  /// The box of every slide has the card picture's shape, so the slides
  /// are the same height.
  static const _aspectRatio = 999 / 828;

  /// The brackets' frame, upright like the bottle it holds.
  static const _frameAspectRatio = 0.9;

  final FirstRecordInviteSlide slide;
  final double width;
  final Animation<double> scan;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      slide.picture,
      fit: slide.scanned ? BoxFit.contain : BoxFit.cover,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
    return Container(
      width: width,
      height: width / _aspectRatio,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadii.largeCard),
        boxShadow: AppShadows.card,
      ),
      child: !slide.scanned
          ? image
          : Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: AspectRatio(
                  aspectRatio: _frameAspectRatio,
                  child: CustomPaint(
                    foregroundPainter: _ViewfinderPainter(scan),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s14),
                      child: image,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// The four corner brackets of a camera's frame, and the line that reads
/// the label from the top of the frame to its foot while [scan] runs.
class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter(this.scan) : super(repaint: scan);

  static const _arm = AppSpacing.xl;
  static const _corner = AppRadii.sm;
  static const _stroke = 3.0;
  static const _trail = AppSpacing.xxxl;

  final Animation<double> scan;

  @override
  void paint(Canvas canvas, Size size) {
    final brackets = Paint()
      ..color = AppColors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    // One corner drawn at the top left, then mirrored to the other three.
    final corner = Path()
      ..moveTo(0, _arm)
      ..lineTo(0, _corner)
      ..arcToPoint(
        const Offset(_corner, 0),
        radius: const Radius.circular(_corner),
      )
      ..lineTo(_arm, 0);
    for (final (flipX, flipY) in const <(bool, bool)>[
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      canvas
        ..save()
        ..translate(flipX ? size.width : 0, flipY ? size.height : 0)
        ..scale(flipX ? -1 : 1, flipY ? -1 : 1)
        ..drawPath(corner, brackets)
        ..restore();
    }

    final at = scan.value;
    if (at <= 0 || at >= 1) return;
    final y = size.height * at;
    final lit = Rect.fromLTRB(0, math.max(0, y - _trail), size.width, y);
    canvas
      ..drawRect(
        lit,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              AppColors.actionPrimary.withValues(alpha: 0),
              AppColors.actionPrimary.withValues(alpha: 0.22),
            ],
          ).createShader(lit),
      )
      ..drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = AppColors.actionPrimary
          ..strokeWidth = _stroke / 2
          ..strokeCap = StrokeCap.round,
      );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => old.scan != scan;
}

/// One thing read from the picture: its small grey name, what was read,
/// and the check that pops in once the row has landed.
class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.lands,
    required this.checkPops,
    super.key,
  });

  /// The longest name, 다음 한 잔, in letters: every row's value starts at
  /// the same place.
  static const _labelLetters = 5;

  static final _rise = Tween<Offset>(
    begin: const Offset(0, 0.3),
    end: Offset.zero,
  );

  final String label;
  final String value;
  final Animation<double> lands;
  final Animation<double> checkPops;

  @override
  Widget build(BuildContext context) {
    const labelStyle = AppTextStyles.labelSmall;
    final labelWidth =
        MediaQuery.textScalerOf(context).scale(labelStyle.fontSize!) *
        _labelLetters;
    return FadeTransition(
      opacity: lands,
      child: SlideTransition(
        position: _rise.animate(lands),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(AppRadii.chip),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: labelWidth,
                child: Text(
                  label,
                  maxLines: 1,
                  style: labelStyle.copyWith(color: AppColors.textTertiary),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Kept whole on one line: a narrow phone draws it smaller.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: AppTextStyles.itemTitle,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ScaleTransition(scale: checkPops, child: const _Check()),
            ],
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check();

  @override
  Widget build(BuildContext context) => Container(
    width: AppSizes.iconMd,
    height: AppSizes.iconMd,
    decoration: const BoxDecoration(
      color: AppColors.preferencePrimary,
      shape: BoxShape.circle,
    ),
    child: const Icon(
      Icons.check_rounded,
      size: AppSizes.iconXs,
      color: AppColors.textOnPrimary,
    ),
  );
}
