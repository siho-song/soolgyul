import 'dart:ui' show Color;

import '../../../design/app_tokens.dart';

/// The three tiles a taste letter is drawn with, and what one says.

typedef SoolgyulLetter = ({String asset, String letter, Color color});

const SoolgyulLetter wineLetter = (
  asset: 'assets/component_assets/home_soolgyul_letter_wine_processed.png',
  letter: 'I',
  color: AppColors.homeLetterWine,
);

const SoolgyulLetter oliveLetter = (
  asset: 'assets/component_assets/home_soolgyul_letter_green_processed.png',
  letter: 'S',
  color: AppColors.homeLetterOlive,
);

const SoolgyulLetter unknownLetter = (
  asset: 'assets/component_assets/home_soolgyul_letter_unknown_processed.png',
  letter: '?',
  color: AppColors.homeLetterUnknown,
);

class LetterMeaning {
  const LetterMeaning({
    required this.letter,
    required this.title,
    required this.body,
  });

  final SoolgyulLetter letter;
  final String title;
  final String body;
}
