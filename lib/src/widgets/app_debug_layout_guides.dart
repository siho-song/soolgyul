import 'package:flutter/material.dart';

import '../design/app_layout.dart';

class AppDebugLayoutGuides extends StatelessWidget {
  const AppDebugLayoutGuides({required this.headerHeight, super.key});

  final double headerHeight;

  @override
  Widget build(BuildContext context) {
    final safeArea = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = AppLayout.screenHorizontalPadding(
          constraints.maxWidth,
        );
        return CustomPaint(
          painter: _AppDebugLayoutGuidePainter(
            headerHeight: headerHeight,
            contentHorizontalPadding: horizontalPadding,
            headerHorizontalPadding: AppLayout.headerHorizontalPadding,
            safeArea: safeArea,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _AppDebugLayoutGuidePainter extends CustomPainter {
  const _AppDebugLayoutGuidePainter({
    required this.headerHeight,
    required this.contentHorizontalPadding,
    required this.headerHorizontalPadding,
    required this.safeArea,
  });

  final double headerHeight;
  final double contentHorizontalPadding;
  final double headerHorizontalPadding;
  final EdgeInsets safeArea;

  @override
  void paint(Canvas canvas, Size size) {
    final headerLine = Paint()
      ..color = const Color(0xCCF57C00)
      ..strokeWidth = 1;
    final contentLine = Paint()
      ..color = const Color(0xCC00897B)
      ..strokeWidth = 1;
    final screenLine = Paint()
      ..color = const Color(0x997E57C2)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final safeAreaFill = Paint()..color = const Color(0x1A1976D2);
    final safeAreaLine = Paint()
      ..color = const Color(0xCC1976D2)
      ..strokeWidth = 1;

    if (safeArea.top > 0) {
      canvas
        ..drawRect(Rect.fromLTWH(0, 0, size.width, safeArea.top), safeAreaFill)
        ..drawLine(
          Offset(0, safeArea.top),
          Offset(size.width, safeArea.top),
          safeAreaLine,
        );
      _paintLabel(
        canvas,
        'SAFE TOP ${safeArea.top.toStringAsFixed(0)}',
        const Offset(4, 3),
        const Color(0xFF1976D2),
      );
    }

    if (safeArea.bottom > 0) {
      final safeBottomStart = size.height - safeArea.bottom;
      canvas
        ..drawRect(
          Rect.fromLTWH(0, safeBottomStart, size.width, safeArea.bottom),
          safeAreaFill,
        )
        ..drawLine(
          Offset(0, safeBottomStart),
          Offset(size.width, safeBottomStart),
          safeAreaLine,
        );
      _paintLabel(
        canvas,
        'SAFE BOTTOM ${safeArea.bottom.toStringAsFixed(0)}',
        Offset(4, safeBottomStart + 3),
        const Color(0xFF1976D2),
      );
    }

    if (headerHeight > 0) {
      final headerBottom = safeArea.top + headerHeight;
      canvas.drawLine(
        Offset(0, headerBottom),
        Offset(size.width, headerBottom),
        headerLine,
      );
      _paintLabel(
        canvas,
        'HEADER ${headerHeight.toStringAsFixed(0)}',
        Offset(4, safeArea.top + 3),
        const Color(0xFFF57C00),
      );
      canvas
        ..drawLine(
          Offset(headerHorizontalPadding, safeArea.top),
          Offset(headerHorizontalPadding, headerBottom),
          headerLine,
        )
        ..drawLine(
          Offset(size.width - headerHorizontalPadding, safeArea.top),
          Offset(size.width - headerHorizontalPadding, headerBottom),
          headerLine,
        );
      _paintLabel(
        canvas,
        'HEADER PAD ${headerHorizontalPadding.toStringAsFixed(0)}',
        Offset(headerHorizontalPadding + 4, headerBottom - 13),
        const Color(0xFFF57C00),
      );
    }

    final contentStart = safeArea.top + headerHeight;
    final contentEnd = size.height - safeArea.bottom;
    canvas
      ..drawRect(Offset.zero & size, screenLine)
      ..drawLine(
        Offset(contentHorizontalPadding, contentStart),
        Offset(contentHorizontalPadding, contentEnd),
        contentLine,
      )
      ..drawLine(
        Offset(size.width - contentHorizontalPadding, contentStart),
        Offset(size.width - contentHorizontalPadding, contentEnd),
        contentLine,
      );

    _paintLabel(
      canvas,
      'CONTENT PAD ${contentHorizontalPadding.toStringAsFixed(0)}',
      Offset(contentHorizontalPadding + 4, contentStart + 4),
      const Color(0xFF00897B),
    );
    _paintLabel(
      canvas,
      'iPhone 17  ${size.width.toStringAsFixed(0)} × ${size.height.toStringAsFixed(0)}',
      Offset(4, size.height - safeArea.bottom - 14),
      const Color(0xFF7E57C2),
    );
  }

  void _paintLabel(Canvas canvas, String text, Offset offset, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          backgroundColor: const Color(0xCCFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_AppDebugLayoutGuidePainter oldDelegate) {
    return oldDelegate.headerHeight != headerHeight ||
        oldDelegate.contentHorizontalPadding != contentHorizontalPadding ||
        oldDelegate.headerHorizontalPadding != headerHorizontalPadding ||
        oldDelegate.safeArea != safeArea;
  }
}
