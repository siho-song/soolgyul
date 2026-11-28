import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The line icons of the app. Each value is one file in
/// `assets/icons/line/`, drawn in ink and coloured where it is used.
enum AppIconAsset {
  bell('bell'),
  bookmark('bookmark'),
  bookmarkFill('bookmark_fill'),
  calendar('calendar'),
  camera('camera'),

  /// A check in a circle.
  check('check'),

  /// The check alone.
  checkMark('check_mark'),
  chevronUp('chevron_up'),
  close('close'),
  edit('edit'),

  /// A chevron pointing down.
  expand('expand'),
  heart('heart'),
  heartFill('heart_fill'),
  info('info'),
  instagram('instagram'),
  memo('memo'),
  moreVert('more_vert'),
  next('next'),
  previous('back'),
  search('search'),
  smooth('smooth'),
  stack('stack'),
  star('star'),
  starFill('star_fill'),

  /// A star with its left half filled.
  starHalf('star_half'),
  wine('wine'),

  // The bottom bar's tabs.
  navHome('nav_home'),
  navRecord('nav_record'),
  navExplore('nav_explore'),
  navProfile('nav_profile');

  const AppIconAsset(this.fileName);

  final String fileName;
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
    Widget artwork = SvgPicture.asset(
      'assets/icons/line/${icon.fileName}.svg',
      width: resolvedSize,
      height: resolvedSize,
      fit: BoxFit.contain,
      colorFilter: resolvedColor == null
          ? null
          : ColorFilter.mode(resolvedColor, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );

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
