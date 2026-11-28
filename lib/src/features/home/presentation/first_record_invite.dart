import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_page_indicator.dart';
import 'first_record_invite_slide.dart';

/// What the home shows a member who has no record yet, in place of its
/// boxes: two slides on what a record gives (a 술결 card, then a bottle's
/// fit from a photo of its label) and the button that starts the first
/// record under both.
///
/// A slide plays its sequence, rests, and the other comes by itself; a
/// swipe brings the other at once and plays it from its start. With
/// reduced motion a slide shows whole and stays until it is swiped.
class FirstRecordInvite extends StatefulWidget {
  const FirstRecordInvite({required this.onStart, super.key});

  /// Starts a record, as 기록하기 at the top of the home does.
  final VoidCallback onStart;

  static const slides = <FirstRecordInviteSlide>[
    FirstRecordInviteSlide(
      picture: 'assets/images/home/first_record_card.webp',
      rows: <({String label, String value})>[
        (label: '내 취향', value: '선명한 스위트 러버'),
        (label: '좋았던 점', value: '말린 과일·바닐라 향, 단맛'),
        (label: '다음 한 잔', value: '단맛 · 말린 과일 향 · 바닐라 향'),
      ],
      headline: '한 잔이면 내 취향이 보여요',
      description: '마신 술을 기록하면 왜 좋았는지,\n다음엔 무엇을 고르면 될지 알려드려요',
    ),
    FirstRecordInviteSlide(
      picture: 'assets/images/home/first_record_bottle.webp',
      scanned: true,
      rows: <({String label, String value})>[
        (label: '이름', value: '발베니 더블우드 12년'),
        (label: '종류', value: '싱글 몰트 위스키'),
        (label: '궁합', value: '딱 맞는 PICK !'),
      ],
      headline: '라벨만 찍으면 나와 맞는지 알려드려요',
      description: '기록해 둔 취향을 바탕으로\n사기 전에 잘 맞는 술인지 판정해 드려요',
    ),
  ];

  /// How long a slide stays, its sequence over, before the other comes.
  static final rest = AppDurations.slow * 7;

  @override
  State<FirstRecordInvite> createState() => _FirstRecordInviteState();
}

class _FirstRecordInviteState extends State<FirstRecordInvite>
    with SingleTickerProviderStateMixin {
  static const _slides = FirstRecordInvite.slides;

  /// The room between two slides while one gives way to the other.
  static const _slideGap = AppSpacing.xxl;

  /// A flick faster than this, in pixels a second, turns the slide however
  /// short it was.
  static const _flickSpeed = 300.0;

  /// The picture's width: as wide as the screen's height leaves room for
  /// the button under the slide, within these.
  static const _pictureWidthShare = 0.34;
  static const _pictureMinWidth = 200.0;
  static const _pictureMaxWidth = 300.0;

  /// Where the slides stand: 0 with the first in place, 1 with the second.
  late final AnimationController _place = AnimationController(
    vsync: this,
    upperBound: _slides.length - 1.0,
  );

  /// How many times each slide was asked to play its sequence.
  final _runs = List<int>.filled(_slides.length, 0);

  Timer? _rest;
  var _current = 0;
  var _dragging = false;

  /// Whether the phone asks for reduced motion; `null` before it is read.
  bool? _still;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _still) return;
    _still = still;
    _rest?.cancel();
    if (still) {
      _place.value = _current.toDouble();
    } else {
      _runs[_current]++;
    }
  }

  @override
  void dispose() {
    _rest?.cancel();
    _place.dispose();
    super.dispose();
  }

  /// Brings slide [index] in place and plays its sequence from the start.
  void _show(int index) {
    _rest?.cancel();
    final still = _still ?? false;
    setState(() {
      _current = index;
      if (!still) _runs[index]++;
    });
    if (still) {
      _place.value = index.toDouble();
    } else {
      _place.animateTo(
        index.toDouble(),
        duration: AppDurations.slow,
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// The slide in place has played: it rests, then the other comes. A
  /// timer waits, not an animation, so nothing is drawn while it rests.
  void _played(int index) {
    if (index != _current || _dragging) return;
    _rest?.cancel();
    _rest = Timer(FirstRecordInvite.rest, () {
      if (mounted) _show((_current + 1) % _slides.length);
    });
  }

  void _dragStarted() {
    _dragging = true;
    _rest?.cancel();
    _place.stop();
  }

  void _dragEnded(double velocity) {
    _dragging = false;
    final flicked = velocity.abs() >= _flickSpeed;
    final target = flicked
        ? _current + (velocity < 0 ? 1 : -1)
        : _place.value.round();
    _show(target.clamp(0, _slides.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final pictureWidth =
        (MediaQuery.sizeOf(context).height * _pictureWidthShare).clamp(
          _pictureMinWidth,
          _pictureMaxWidth,
        );
    return Column(
      key: const ValueKey<String>('first-record-invite'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) {
            final travel = constraints.maxWidth + _slideGap;
            return GestureDetector(
              key: const ValueKey<String>('first-record-invite-slides'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _dragStarted(),
              onHorizontalDragUpdate: (details) =>
                  _place.value -= details.primaryDelta! / travel,
              onHorizontalDragEnd: (details) =>
                  _dragEnded(details.primaryVelocity ?? 0),
              onHorizontalDragCancel: () => _dragEnded(0),
              // Both slides are laid out, so the taller gives the height
              // and nothing under them moves when one gives way.
              child: Stack(
                fit: StackFit.passthrough,
                children: <Widget>[
                  for (var index = 0; index < _slides.length; index++)
                    _placed(index, travel, pictureWidth),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: AppPageIndicator(count: _slides.length, activeIndex: _current),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          key: const ValueKey<String>('first-record-invite-start'),
          label: '첫 한 잔 기록하기',
          size: AppButtonSize.prominent,
          onPressed: widget.onStart,
        ),
      ],
    );
  }

  /// Slide [index] where [_place] puts it: one slide's width to the side
  /// for each step away, and fainter the farther, so the slide not in
  /// place is not seen beside the page either.
  Widget _placed(int index, double travel, double pictureWidth) =>
      AnimatedBuilder(
        animation: _place,
        builder: (context, slide) {
          final away = index - _place.value;
          return Transform.translate(
            offset: Offset(away * travel, 0),
            child: Opacity(
              opacity: (1 - away.abs()).clamp(0.0, 1.0),
              child: slide,
            ),
          );
        },
        child: ExcludeSemantics(
          excluding: index != _current,
          child: FirstRecordInviteSlideView(
            key: ValueKey<String>('first-record-invite-slide-$index'),
            index: index,
            slide: _slides[index],
            run: _runs[index],
            still: _still ?? false,
            pictureWidth: pictureWidth,
            onDone: () => _played(index),
          ),
        ),
      );
}
