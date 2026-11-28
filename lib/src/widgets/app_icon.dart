import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The line icons of the app. Each value but [close] is one file in
/// `assets/icons/line/`.
enum AppIconAsset {
  bell('bell'),
  calendar('calendar'),
  camera('camera'),
  check('check'),
  edit('edit'),
  expand('expand'),
  info('info'),
  instagram('instagram'),
  memo('memo'),
  next('next'),
  photoUpload('photo_upload'),
  previous('back'),
  sake('sake'),
  save('save'),
  search('search'),
  smooth('smooth'),
  traditional('traditional'),
  whisky('whisky'),
  wine('wine'),

  /// Flutter's own rounded ×; it has no file.
  close(null),

  // The bottom bar's own 24px stroke drawings.
  navHome('nav_home'),
  navRecord('nav_record'),
  navExplore('nav_explore'),
  navProfile('nav_profile');

  const AppIconAsset(this.fileName);

  final String? fileName;
}

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.rotationTurns = 0,
  });

  final AppIconAsset icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final double rotationTurns;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24;
    final resolvedColor = color ?? iconTheme.color;
    final resolvedOpacity = iconTheme.opacity ?? 1;
    Widget artwork = switch (icon.fileName) {
      null => Icon(
        Icons.close_rounded,
        size: resolvedSize,
        color: resolvedColor,
        semanticLabel: semanticLabel,
      ),
      final fileName => SvgPicture.asset(
        'assets/icons/line/$fileName.svg',
        width: resolvedSize,
        height: resolvedSize,
        fit: BoxFit.contain,
        colorFilter: resolvedColor == null
            ? null
            : ColorFilter.mode(resolvedColor, BlendMode.srcIn),
        semanticsLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
      ),
    };

    if (rotationTurns != 0) {
      artwork = Transform.rotate(
        angle: rotationTurns * math.pi * 2,
        child: artwork,
      );
    }

    if (resolvedOpacity < 1) {
      artwork = Opacity(opacity: resolvedOpacity, child: artwork);
    }

    return SizedBox.square(dimension: resolvedSize, child: artwork);
  }
}
