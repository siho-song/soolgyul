import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../data/taste_fit_verdict.dart';

/// Every verdict's headline is written in the app's wine; only a bottle
/// without data is muted.
abstract final class TasteFitColors {
  static Color titleOf(TasteFitBadge badge) => switch (badge) {
    TasteFitBadge.noInfo => AppColors.textSupporting,
    _ => AppColors.actionPrimary,
  };
}

/// The verdict's face: a smile for a match, a plain face for plain, a frown
/// for a caution. A bottle without data shows no face.
class TasteFitBadgeIcon extends StatelessWidget {
  const TasteFitBadgeIcon(this.badge, {this.size = 24, super.key});

  final TasteFitBadge badge;
  final double size;

  static String? assetOf(TasteFitBadge badge) => switch (badge) {
    TasteFitBadge.star => 'assets/component_assets/taste_fit/smile.png',
    TasteFitBadge.neutral => 'assets/component_assets/taste_fit/neutral.png',
    TasteFitBadge.caution => 'assets/component_assets/taste_fit/frown.png',
    TasteFitBadge.noInfo => null,
  };

  @override
  Widget build(BuildContext context) {
    final asset = assetOf(badge);
    if (asset == null) return SizedBox.square(dimension: size);
    return Image.asset(
      asset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
  }
}

/// The face at the right of a search result row, read aloud by its verdict;
/// `no_info` shows nothing.
class TasteFitRowBadge extends StatelessWidget {
  const TasteFitRowBadge(this.badge, {super.key});

  static String? labelOf(TasteFitBadge badge) => switch (badge) {
    TasteFitBadge.star => '취향 저격',
    TasteFitBadge.caution => '낯설 수 있어요',
    TasteFitBadge.neutral => '편안해요',
    TasteFitBadge.noInfo => null,
  };

  final TasteFitBadge badge;

  @override
  Widget build(BuildContext context) {
    final label = labelOf(badge);
    if (label == null) return const SizedBox.shrink();
    return Semantics(label: label, child: TasteFitBadgeIcon(badge, size: 26));
  }
}
