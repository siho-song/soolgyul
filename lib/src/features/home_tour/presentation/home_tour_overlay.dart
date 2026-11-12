import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';

/// The places on the home the tour points at. The home and the bottom
/// navigation hang these keys on their parts.
class HomeTourTargets {
  final record = GlobalKey(debugLabel: 'home-tour-record');
  final home = GlobalKey(debugLabel: 'home-tour-home');
  final tasteFit = GlobalKey(debugLabel: 'home-tour-taste-fit');
  final letters = GlobalKey(debugLabel: 'home-tour-letters');
  final guides = GlobalKey(debugLabel: 'home-tour-guides');

  /// The example guide's box of marks: where its light may stop.
  final guidesLevels = GlobalKey(debugLabel: 'home-tour-guides-levels');
}

/// What a member without a card is shown, in this order: where a record
/// starts, the card it gives, and the home that card fills.
enum HomeTourStep {
  record(title: '술결은 기록에서 시작해요', body: '마신 술 하나를 고르고,\n느낀 점을 가볍게 남겨보세요.'),
  card(
    title: '기록하면 술결 카드를 받아요',
    body: '내 입맛에 왜 맞았는지,\n다음엔 뭘 마시면 좋을지 분석해 드려요.',
    example: true,
  ),
  tasteFit(
    title: '살까 말까 고민되는 술이 있나요?',
    body: '라벨을 촬영하거나 검색해 보세요.\n내 취향과 얼마나 잘 맞을지 미리 알려드려요.',
  ),
  letters(
    title: '나를 표현하는 네 글자 취향',
    body: '마신 술이 쌓일수록 또렷해져요.\n향 · 단맛 · 무게 · 여운 순서로 완성돼요.',
    example: true,
  ),
  guides(
    title: '실패 없는 다음 한 잔 가이드',
    body: '내 취향에 맞춘 추천 조합이에요.\n와인 바틀샵이나 식당에서 꺼내보세요.',
    example: true,
  ),
  start(
    title: '이제 첫 술결을 남겨볼까요?',
    body: '최근에 마신 술 하나로 가볍게 시작해요.',
    later: '나중에',
    go: '첫 술결 남기기',
  );

  const HomeTourStep({
    required this.title,
    required this.body,
    this.example = false,
    this.later = '건너뛰기',
    this.go = '다음',
  });

  final String title;
  final String body;

  /// Whether what the step points at is made up, and says so.
  final bool example;

  /// The two buttons: the one that ends the tour and the one that goes on.
  final String later;
  final String go;

  /// Whether the step points at the 기록 button, not at a part of the home.
  bool get onRecordButton =>
      this == HomeTourStep.record || this == HomeTourStep.start;

  GlobalKey? target(HomeTourTargets targets) => switch (this) {
    HomeTourStep.record || HomeTourStep.start => targets.record,
    HomeTourStep.card => null,
    HomeTourStep.tasteFit => targets.tasteFit,
    HomeTourStep.letters => targets.letters,
    HomeTourStep.guides => targets.guides,
  };

  /// Where the light may stop when the part is too tall to light whole:
  /// above this, so no box is lit half.
  GlobalKey? stop(HomeTourTargets targets) =>
      this == HomeTourStep.guides ? targets.guidesLevels : null;
}

/// [text] with its words kept whole: a line breaks at a space, never inside
/// a word, which Korean text otherwise allows.
String wordsKept(String text) => text
    .split('\n')
    .map(
      (line) =>
          line.split(' ').map((word) => word.characters.join('⁠')).join(' '),
    )
    .join('\n');

/// How the tour ended.
enum HomeTourEnd { closed, startRecord }

/// The dimmed layer over the home: one part stays lit, a bubble explains
/// it, 다음 moves on.
class HomeTourOverlay extends StatefulWidget {
  const HomeTourOverlay({
    required this.targets,
    required this.exampleCard,
    required this.onEnd,
    super.key,
  });

  final HomeTourTargets targets;

  /// The example card's screen, drawn cut off in a frame on the card step.
  final Widget exampleCard;
  final ValueChanged<HomeTourEnd> onEnd;

  @override
  State<HomeTourOverlay> createState() => HomeTourOverlayState();
}

class HomeTourOverlayState extends State<HomeTourOverlay> {
  static const _move = AppDurations.standard;

  /// A bubble with a two-line body, its pointer and the gap to the part.
  static const _bubbleRoom = 184.0;
  static const _bubbleGap = AppSpacing.s14;
  static const _side = AppSpacing.lg;

  var _step = HomeTourStep.values.first;

  /// The lit part, in this layer's coordinates; `null` lights nothing.
  Rect? _hole;

  /// The home's page while a part of it is lit; the light stays inside.
  Rect? _shown;

  /// Where the light may stop on a part too tall to light whole.
  Rect? _stop;
  int _locating = 0;

  @override
  void initState() {
    super.initState();
    _locateAfterFrame();
  }

  /// Goes one step back; `false` on the first step.
  bool back() {
    if (_step.index == 0) return false;
    _show(HomeTourStep.values[_step.index - 1]);
    return true;
  }

  void _next() {
    if (_step == HomeTourStep.values.last) {
      widget.onEnd(HomeTourEnd.startRecord);
      return;
    }
    _show(HomeTourStep.values[_step.index + 1]);
  }

  void _close() => widget.onEnd(HomeTourEnd.closed);

  void _show(HomeTourStep step) {
    setState(() => _step = step);
    _locateAfterFrame();
  }

  void _locateAfterFrame() {
    final run = ++_locating;
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate(run));
  }

  /// Brings the step's part on screen and lights it. The home may still be
  /// laying out its example, so the place is read again once it settles.
  Future<void> _locate(int run) async {
    if (!mounted || run != _locating) return;
    final target = _step.target(widget.targets)?.currentContext;
    if (target == null) {
      setState(() => _hole = null);
      return;
    }
    if (!_step.onRecordButton) {
      await Scrollable.ensureVisible(
        target,
        duration: _move,
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted || !target.mounted || run != _locating) return;
    _read(target);
    await Future<void>.delayed(_move);
    if (!mounted || !target.mounted || run != _locating) return;
    _read(target);
  }

  void _read(BuildContext target) {
    final hole = _placeOf(target);
    if (hole == null) return;
    // A part of the home is lit only as far as the home shows it: not
    // under the header or the bottom navigation.
    final page = widget.targets.home.currentContext;
    final shown = page != null && !_step.onRecordButton ? _placeOf(page) : null;
    final stopAt = _step.stop(widget.targets)?.currentContext;
    final stop = stopAt == null ? null : _placeOf(stopAt);
    if (hole != _hole || shown != _shown || stop != _stop) {
      setState(() {
        _hole = hole;
        _shown = shown;
        _stop = stop;
      });
    }
  }

  Rect? _placeOf(BuildContext part) {
    final box = part.findRenderObject();
    final layer = context.findRenderObject();
    if (box is! RenderBox || layer is! RenderBox || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: layer) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final hole = _step == HomeTourStep.card
              ? null
              : _lit(_hole, size, safe);
          return Stack(
            children: <Widget>[
              // Taps stop here: nothing under the tour is pressed.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: hole == null
                      ? const CustomPaint(painter: _DimPainter(null, 0))
                      : TweenAnimationBuilder<Rect?>(
                          tween: RectTween(end: hole),
                          duration: _move,
                          curve: Curves.easeOutCubic,
                          builder: (context, rect, _) =>
                              CustomPaint(painter: _DimPainter(rect, _radius)),
                        ),
                ),
              ),
              if (_step == HomeTourStep.card)
                _cardStep(size, safe)
              else if (hole != null)
                _bubbleBy(hole, size, safe),
            ],
          );
        },
      ),
    );
  }

  double get _radius =>
      _step.onRecordButton ? AppRadii.card : AppRadii.compactCard + 4;

  /// The lit rectangle: a little wider than the part and inside the home's
  /// page. A part too tall to leave the bubble room is lit from its top
  /// only as far as the bubble fits under it, and ends above the step's
  /// stop when that starts before there.
  Rect? _lit(Rect? part, Size size, EdgeInsets safe) {
    if (part == null) return null;
    final lit = part
        .inflate(AppSpacing.s6)
        .intersect(_shown ?? Offset.zero & size);
    final below = size.height - safe.bottom - lit.bottom;
    final above = lit.top - safe.top;
    if (below >= _bubbleRoom || above >= _bubbleRoom) return lit;
    final room = size.height - safe.bottom - _bubbleRoom;
    final stop = _stop;
    final cut = stop != null && stop.top > lit.top && stop.top < room
        ? stop.top - AppSpacing.s6
        : room;
    return Rect.fromLTRB(lit.left, lit.top, lit.right, cut);
  }

  Widget _bubble() => _Bubble(step: _step, onClose: _close, onNext: _next);

  Widget _bubbleBy(Rect hole, Size size, EdgeInsets safe) {
    final below = size.height - safe.bottom - hole.bottom;
    final pointer = (hole.center.dx - _side - _Pointed.width / 2).clamp(
      AppSpacing.xxl,
      size.width - _side * 2 - AppSpacing.xxl - _Pointed.width,
    );
    if (below >= _bubbleRoom) {
      return Positioned(
        left: _side,
        right: _side,
        top: hole.bottom + _bubbleGap,
        child: _Pointed(up: true, at: pointer, child: _bubble()),
      );
    }
    return Positioned(
      left: _side,
      right: _side,
      bottom: size.height - hole.top + _bubbleGap,
      child: _Pointed(up: false, at: pointer, child: _bubble()),
    );
  }

  /// The example card, cut off where a frame half the screen high cuts it.
  Widget _cardStep(Size size, EdgeInsets safe) {
    const side = AppSpacing.xxl + AppSpacing.xs;
    return Positioned.fill(
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: size.width - side * 2,
              height: (size.height - safe.vertical) / 2,
              child: _CardFrame(
                screenWidth: size.width,
                child: widget.exampleCard,
              ),
            ),
            const SizedBox(height: _bubbleGap),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _side),
              child: _Pointed(
                up: true,
                at: size.width / 2 - _side - _Pointed.width / 2,
                child: _bubble(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A screen drawn at the phone's width, shrunk to the frame and cut off at
/// its lower edge, where it fades out: the screen goes on below.
class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.screenWidth, required this.child});

  final double screenWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = constraints.maxWidth / screenWidth;
      final clear = AppColors.surfaceCanvas.withValues(alpha: 0);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.card),
          boxShadow: AppShadows.floatingControl,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: screenWidth,
                maxWidth: screenWidth,
                minHeight: constraints.maxHeight / scale,
                maxHeight: constraints.maxHeight / scale,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        removeBottom: true,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: AppSpacing.massive,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[clear, AppColors.surfaceCanvas],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A bubble with the small triangle that points at the lit part.
class _Pointed extends StatelessWidget {
  const _Pointed({required this.up, required this.at, required this.child});

  static const width = AppSpacing.lg;

  final bool up;

  /// The triangle's left edge, from the bubble's left edge.
  final double at;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pointer = Padding(
      padding: EdgeInsets.only(left: at),
      child: CustomPaint(
        size: const Size(width, AppSpacing.sm),
        painter: _PointerPainter(up: up),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: up ? <Widget>[pointer, child] : <Widget>[child, pointer],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.step,
    required this.onClose,
    required this.onNext,
  });

  final HomeTourStep step;
  final VoidCallback onClose;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Container(
      key: ValueKey<String>('home-tour-bubble-${step.name}'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg + AppSpacing.xxs,
        AppSpacing.s14,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfacePrimary,
        borderRadius: BorderRadius.circular(AppRadii.compactCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  wordsKept(step.title),
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              if (step.example) ...const <Widget>[
                SizedBox(width: AppSpacing.sm),
                _ExampleMark(),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.s6),
            child: Text(wordsKept(step.body), style: AppTextStyles.detail),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Text(
                '${step.index + 1} / ${HomeTourStep.values.length}',
                style: AppTextStyles.caption,
              ),
              const Spacer(),
              AppButton(
                key: const ValueKey<String>('home-tour-close'),
                label: step.later,
                variant: AppButtonVariant.tertiary,
                size: AppButtonSize.compact,
                widthMode: AppButtonWidthMode.intrinsic,
                onPressed: onClose,
              ),
              const SizedBox(width: AppSpacing.xs),
              AppButton(
                key: const ValueKey<String>('home-tour-next'),
                label: step.go,
                size: AppButtonSize.compact,
                widthMode: AppButtonWidthMode.intrinsic,
                onPressed: onNext,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ExampleMark extends StatelessWidget {
  const _ExampleMark();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadii.chip),
    ),
    child: Text(
      '예시',
      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
    ),
  );
}

/// The dimmed sheet with one rounded hole: the lit part.
class _DimPainter extends CustomPainter {
  const _DimPainter(this.hole, this.radius);

  final Rect? hole;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (hole case final hole?) {
      dim.addRRect(RRect.fromRectAndRadius(hole, Radius.circular(radius)));
    }
    canvas.drawPath(dim, Paint()..color = AppColors.spotlightScrim);
  }

  @override
  bool shouldRepaint(_DimPainter old) =>
      old.hole != hole || old.radius != radius;
}

class _PointerPainter extends CustomPainter {
  const _PointerPainter({required this.up});

  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final tip = up ? 0.0 : size.height;
    final base = up ? size.height : 0.0;
    final path = Path()
      ..moveTo(0, base)
      ..lineTo(size.width / 2, tip)
      ..lineTo(size.width, base)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.surfacePrimary);
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.up != up;
}
