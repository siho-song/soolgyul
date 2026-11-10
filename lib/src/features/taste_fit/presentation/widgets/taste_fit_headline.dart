import '../../../../design/app_tokens.dart';
import 'package:flutter/material.dart';

import '../../data/taste_fit_verdict.dart';
import 'taste_fit_badge.dart';

/// "딱 맞는 PICK !" and then its face, right under the product name, on
/// the detail and on the card a label photo asks about.
class TasteFitHeadline extends StatelessWidget {
  const TasteFitHeadline({required this.verdict, super.key});

  final TasteFitVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final badge = verdict.badge;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Flexible(
          child: Text(
            verdict.headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: TasteFitColors.titleOf(badge),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s6),
        TasteFitBadgeIcon(badge, size: 22),
      ],
    );
  }
}
