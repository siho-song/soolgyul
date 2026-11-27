import 'package:flutter/widgets.dart';

import '../../adaptive/onboarding_aroma_menu.dart';

/// How wide the picture of a question's aroma chip is, at the normal text
/// size.
const aromaChipPictureSize = 20.0;

/// The picture that goes before an aroma's name, in a square [size] wide at
/// the normal text size. It grows with the reader's text size, as the name
/// beside it does.
class AromaPicture extends StatelessWidget {
  const AromaPicture(this.chip, {required this.size, super.key});

  /// The picture of [chip], or null for a name that is no chip's.
  static Widget? of(OnboardingAromaChip? chip, {required double size}) =>
      chip == null ? null : AromaPicture(chip, size: size);

  final OnboardingAromaChip chip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.textScalerOf(context).scale(size);
    return Image.asset(
      chip.picture,
      width: side,
      height: side,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
  }
}
