import 'package:flutter/material.dart';

import '../design/app_tokens.dart';

/// What a drink's photo frame shows when the drink has no photo or the
/// photo did not load: the same drawing everywhere, on the frame's own
/// background.
class DrinkPhotoPlaceholder extends StatelessWidget {
  const DrinkPhotoPlaceholder({super.key});

  static const asset = 'assets/images/drink_photo_placeholder.png';

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(AppSpacing.xs),
    child: Center(
      child: Image(
        image: AssetImage(asset),
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    ),
  );
}
