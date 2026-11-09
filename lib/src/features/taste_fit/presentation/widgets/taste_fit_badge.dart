import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../widgets/app_icon.dart';
import '../../data/taste_fit_verdict.dart';

/// Every verdict is drawn in the app's wine; only a bottle without data is muted.
abstract final class TasteFitColors {
  static Color iconOf(TasteFitBadge badge) => switch (badge) {
    TasteFitBadge.noInfo => AppColors.textSupporting,
    _ => AppColors.actionPrimary,
  };

  static Color titleOf(TasteFitBadge badge) => iconOf(badge);
}

/// The verdict's heart: full for a match, half for plain, empty for a
/// caution. A bottle without data shows no heart.
class TasteFitBadgeIcon extends StatelessWidget {
  const TasteFitBadgeIcon(this.badge, {this.size = 22, super.key});

  final TasteFitBadge badge;
  final double size;

  static AppIconAsset? assetOf(TasteFitBadge badge) => switch (badge) {
    TasteFitBadge.star => AppIconAsset.heartFull,
    TasteFitBadge.neutral => AppIconAsset.heartHalf,
    TasteFitBadge.caution => AppIconAsset.heartEmpty,
    TasteFitBadge.noInfo => null,
  };

  @override
  Widget build(BuildContext context) {
    final asset = assetOf(badge);
    if (asset == null) return SizedBox.square(dimension: size);
    return AppIcon(
      asset,
      size: size,
      color: TasteFitColors.iconOf(badge),
      weight: AppIconWeight.strong,
    );
  }
}

/// The badge at the right of a search result row; `no_info` shows nothing.
class TasteFitRowBadge extends StatelessWidget {
  const TasteFitRowBadge(this.badge, {super.key});

  static String? labelOf(TasteFitBadge badge) => switch (badge) {
    TasteFitBadge.star => '잘 맞아요',
    TasteFitBadge.caution => '조심',
    TasteFitBadge.neutral => '무난해요',
    TasteFitBadge.noInfo => null,
  };

  final TasteFitBadge badge;

  @override
  Widget build(BuildContext context) {
    final label = labelOf(badge);
    if (label == null) return const SizedBox.shrink();
    return SizedBox(
      width: 48,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TasteFitBadgeIcon(badge),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 10,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: TasteFitColors.iconOf(badge),
            ),
          ),
        ],
      ),
    );
  }
}
