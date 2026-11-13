import 'app_icon_button.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'kept_text.dart';

/// A term's explanation as a small balloon anchored to the tapped word: it
/// opens right above the anchor (below when there is no room), keeps the rest
/// of the screen visible, and closes on its ✕, on any tap outside it, or on
/// the system back before the page under it does.
///
/// [anchor] is the context of the tapped widget (a chip, a word); the balloon
/// is laid out against its rendered box. With [actionLabel] the balloon ends
/// in a text button that closes it and calls [onAction].
Future<void> showTermTooltip(
  BuildContext anchor, {
  required String title,
  required String text,
  String? kind,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final box = anchor.findRenderObject();
  final overlay = Overlay.of(anchor);
  final overlayBox = overlay.context.findRenderObject();
  if (box is! RenderBox || overlayBox is! RenderBox) {
    return Future<void>.value();
  }
  final rect = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlayBox),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlayBox),
  );
  final done = Completer<void>();
  late final OverlayEntry entry;
  void close() {
    if (done.isCompleted) return;
    entry.remove();
    done.complete();
  }

  // A back (the Android button, the iOS swipe, a pop of the page) takes this
  // off the page's route before the page itself.
  final back = LocalHistoryEntry(onRemove: close);
  entry = OverlayEntry(
    builder: (_) => TermTooltipLayer(
      anchor: rect,
      title: title,
      text: text,
      kind: kind,
      actionLabel: actionLabel,
      onAction: onAction,
      onDismiss: () {
        back.remove();
        close();
      },
    ),
  );
  overlay.insert(entry);
  ModalRoute.of(anchor)?.addLocalHistoryEntry(back);
  return done.future;
}

/// The balloon plus the transparent tap-catcher around it.
class TermTooltipLayer extends StatelessWidget {
  const TermTooltipLayer({
    required this.anchor,
    required this.title,
    required this.text,
    required this.onDismiss,
    this.kind,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final Rect anchor;
  final String title;
  final String text;
  final String? kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  static const double maxWidth = 360;
  static const double margin = AppSpacing.lg;
  static const double gap = 6;
  static const double tailWidth = 16;
  static const double tailHeight = 8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(maxWidth, constraints.maxWidth - margin * 2);
        final left = (anchor.center.dx - width / 2).clamp(
          margin,
          constraints.maxWidth - margin - width,
        );
        final padding = MediaQuery.paddingOf(context);
        final roomAbove = anchor.top - gap - padding.top;
        final roomBelow =
            constraints.maxHeight - padding.bottom - anchor.bottom - gap;
        // Above when the anchor sits low enough for a few lines and a long
        // text would not get less room there than below. The balloon is no
        // taller than its side of the anchor; a longer text scrolls inside.
        final above = roomAbove >= math.min(roomBelow, 180);
        final maxHeight = math.max(0.0, above ? roomAbove : roomBelow);
        final tailX = (anchor.center.dx - left).clamp(
          tailWidth,
          width - tailWidth,
        );
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey<String>('term-tooltip-barrier'),
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
              ),
            ),
            CustomSingleChildLayout(
              // The overlay sits outside the page's Material, so the balloon
              // brings its own for text styles and ink.
              delegate: _BalloonLayout(
                anchor: anchor,
                left: left,
                width: width,
                maxHeight: maxHeight,
                above: above,
                gap: gap,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: _Appear(
                  fromBelow: !above,
                  child: _Balloon(
                    width: width,
                    tailX: tailX,
                    above: above,
                    title: title,
                    text: text,
                    kind: kind,
                    onClose: onDismiss,
                    action: switch ((actionLabel, onAction)) {
                      (final label?, final run?) => (
                        label,
                        () {
                          onDismiss();
                          run();
                        },
                      ),
                      _ => null,
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BalloonLayout extends SingleChildLayoutDelegate {
  const _BalloonLayout({
    required this.anchor,
    required this.left,
    required this.width,
    required this.maxHeight,
    required this.above,
    required this.gap,
  });

  final Rect anchor;
  final double left;
  final double width;
  final double maxHeight;
  final bool above;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: width, minWidth: width, maxHeight: maxHeight);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final top = above
        ? anchor.top - gap - childSize.height
        : anchor.bottom + gap;
    final maxTop = math.max(0.0, size.height - childSize.height);
    return Offset(left, top.clamp(0.0, maxTop));
  }

  @override
  bool shouldRelayout(_BalloonLayout old) =>
      old.anchor != anchor ||
      old.left != left ||
      old.width != width ||
      old.maxHeight != maxHeight ||
      old.above != above;
}

/// Fade and slide in over a few frames so the balloon feels attached to the
/// tap rather than popping.
class _Appear extends StatelessWidget {
  const _Appear({required this.child, required this.fromBelow});

  final Widget child;
  final bool fromBelow;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppDurations.fast,
      curve: Curves.easeOut,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * (fromBelow ? -6 : 6)),
          child: child,
        ),
      ),
    );
  }
}

class _Balloon extends StatelessWidget {
  const _Balloon({
    required this.width,
    required this.tailX,
    required this.above,
    required this.title,
    required this.text,
    required this.kind,
    required this.onClose,
    required this.action,
  });

  final double width;
  final double tailX;
  final bool above;
  final String title;
  final String text;
  final String? kind;
  final VoidCallback onClose;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    // Header: the term and its kind on the left, ✕ at the right edge.
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Text.rich(
            TextSpan(
              text: title,
              style: AppTextStyles.cardTitle.copyWith(
                color: AppColors.actionPrimary,
              ),
              children: <InlineSpan>[
                if (kind != null)
                  TextSpan(text: '  $kind', style: AppTextStyles.caption),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppIconButton(
          key: const ValueKey<String>('term-tooltip-close'),
          onPressed: onClose,
          tooltip: '설명 닫기',
          size: AppIconButtonSize.mini,
          child: const CustomPaint(
            size: Size.square(12),
            painter: _CrossPainter(color: AppColors.textTertiary),
          ),
        ),
      ],
    );
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md + AppSpacing.xxs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          header,
          const SizedBox(height: AppSpacing.xs),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: KeptText(text, style: AppTextStyles.modalBody),
            ),
          ),
          if (action case (final label, final run))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey<String>('term-tooltip-action'),
                onPressed: run,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(label),
              ),
            ),
        ],
      ),
    );
    return SizedBox(
      width: width,
      child: CustomPaint(
        painter: _BalloonPainter(tailX: tailX, above: above),
        child: Padding(
          padding: EdgeInsets.only(
            top: above ? 0 : TermTooltipLayer.tailHeight,
            bottom: above ? TermTooltipLayer.tailHeight : 0,
          ),
          child: body,
        ),
      ),
    );
  }
}

/// A bare ✕ of two strokes, with no ring around it.
class _CrossPainter extends CustomPainter {
  const _CrossPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_CrossPainter old) => old.color != color;
}

/// The rounded box with its tail, drawn as one shape so the border runs
/// around the tail too.
class _BalloonPainter extends CustomPainter {
  const _BalloonPainter({required this.tailX, required this.above});

  final double tailX;
  final bool above;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 12.0;
    const tailW = TermTooltipLayer.tailWidth;
    const tailH = TermTooltipLayer.tailHeight;
    final box = above
        ? Rect.fromLTWH(0, 0, size.width, size.height - tailH)
        : Rect.fromLTWH(0, tailH, size.width, size.height - tailH);
    final path = Path();
    if (above) {
      path
        ..moveTo(box.left + radius, box.top)
        ..lineTo(box.right - radius, box.top)
        ..arcToPoint(
          Offset(box.right, box.top + radius),
          radius: const Radius.circular(radius),
        )
        ..lineTo(box.right, box.bottom - radius)
        ..arcToPoint(
          Offset(box.right - radius, box.bottom),
          radius: const Radius.circular(radius),
        )
        ..lineTo(tailX + tailW / 2, box.bottom)
        ..lineTo(tailX, box.bottom + tailH)
        ..lineTo(tailX - tailW / 2, box.bottom)
        ..lineTo(box.left + radius, box.bottom)
        ..arcToPoint(
          Offset(box.left, box.bottom - radius),
          radius: const Radius.circular(radius),
        )
        ..lineTo(box.left, box.top + radius)
        ..arcToPoint(
          Offset(box.left + radius, box.top),
          radius: const Radius.circular(radius),
        )
        ..close();
    } else {
      path
        ..moveTo(box.left + radius, box.top)
        ..lineTo(tailX - tailW / 2, box.top)
        ..lineTo(tailX, box.top - tailH)
        ..lineTo(tailX + tailW / 2, box.top)
        ..lineTo(box.right - radius, box.top)
        ..arcToPoint(
          Offset(box.right, box.top + radius),
          radius: const Radius.circular(radius),
        )
        ..lineTo(box.right, box.bottom - radius)
        ..arcToPoint(
          Offset(box.right - radius, box.bottom),
          radius: const Radius.circular(radius),
        )
        ..lineTo(box.left + radius, box.bottom)
        ..arcToPoint(
          Offset(box.left, box.bottom - radius),
          radius: const Radius.circular(radius),
        )
        ..lineTo(box.left, box.top + radius)
        ..arcToPoint(
          Offset(box.left + radius, box.top),
          radius: const Radius.circular(radius),
        )
        ..close();
    }
    for (final shadow in AppShadows.floatingControl) {
      canvas.drawPath(
        path.shift(shadow.offset),
        Paint()
          ..color = shadow.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurSigma),
      );
    }
    canvas.drawPath(path, Paint()..color = AppColors.surfaceCanvas);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.borderSubtle
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BalloonPainter old) =>
      old.tailX != tailX || old.above != above;
}
