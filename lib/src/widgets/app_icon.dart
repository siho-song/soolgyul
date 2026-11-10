import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum AppIconWeight { auto, regular, medium, strong }

enum AppIconAsset {
  calendar('calendar'),
  camera('camera'),
  check('check'),
  edit('edit'),
  expand('expand'),
  home('home'),
  info('info'),
  instagram('instagram'),
  memo('memo'),
  photoUpload('photo_upload'),
  profile('profile'),
  sake('sake'),
  save('save'),
  search('search'),
  smooth('smooth'),
  tasteDiscovery('taste_discovery'),
  traditional('traditional'),
  whisky('whisky'),
  wine('wine'),

  // Product-level aliases keep screen code semantic without duplicating assets.
  explore('taste_discovery', mediumFileName: 'explore'),
  previous('back'),
  next('next'),
  close('add', rotationTurns: .125);

  const AppIconAsset(
    this.fileName, {
    this.rotationTurns = 0,
    String? mediumFileName,
  }) : mediumFileName = mediumFileName ?? fileName;

  final String fileName;
  final double rotationTurns;

  /// The hand-drawn 24px stroke artwork used at nav-bar weight; an alias may
  /// own one of its own while sharing the traced regular and strong files.
  final String mediumFileName;

  String assetPath(AppIconWeight weight) {
    final name = switch (weight) {
      AppIconWeight.strong => '${fileName}_strong',
      AppIconWeight.medium when supportsMediumWeight =>
        '${mediumFileName}_medium',
      _ => fileName,
    };
    return 'assets/icons/soolgyeol/$name.svg';
  }

  bool get supportsMediumWeight => switch (this) {
    AppIconAsset.home ||
    AppIconAsset.calendar ||
    AppIconAsset.camera ||
    AppIconAsset.memo ||
    AppIconAsset.tasteDiscovery ||
    AppIconAsset.explore ||
    AppIconAsset.profile => true,
    _ => false,
  };
}

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.weight = AppIconWeight.auto,
    this.semanticLabel,
    this.rotationTurns = 0,
  });

  final AppIconAsset icon;
  final double? size;
  final Color? color;
  final AppIconWeight weight;
  final String? semanticLabel;
  final double rotationTurns;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24;
    final resolvedColor = color ?? iconTheme.color;
    final resolvedOpacity = iconTheme.opacity ?? 1;
    // Strong is the default at every size: the thin regular tracing reads as
    // faint next to text, so it is used only where a screen asks for it.
    final resolvedWeight = weight == AppIconWeight.auto
        ? AppIconWeight.strong
        : weight;

    Widget artwork = SvgPicture.asset(
      icon.assetPath(resolvedWeight),
      width: resolvedSize,
      height: resolvedSize,
      fit: BoxFit.contain,
      colorFilter: resolvedColor == null
          ? null
          : ColorFilter.mode(resolvedColor, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );

    final totalRotationTurns = icon.rotationTurns + rotationTurns;
    if (totalRotationTurns != 0) {
      artwork = Transform.rotate(
        angle: totalRotationTurns * math.pi * 2,
        child: artwork,
      );
    }

    if (resolvedOpacity < 1) {
      artwork = Opacity(opacity: resolvedOpacity, child: artwork);
    }

    return SizedBox.square(dimension: resolvedSize, child: artwork);
  }
}
