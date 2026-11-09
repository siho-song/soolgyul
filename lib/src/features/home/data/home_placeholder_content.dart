import 'dart:ui' show Color;

import '../../../design/app_tokens.dart';

/// Hard-coded content for the letter tiles and the letters detail. The
/// placeholder letters stand in while no gateway is given.

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

const soolgyulLetters = <SoolgyulLetter>[
  wineLetter,
  oliveLetter,
  unknownLetter,
  unknownLetter,
];

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

const revealedLetterMeanings = <LetterMeaning>[
  LetterMeaning(
    letter: wineLetter,
    title: '부드럽게 스며드는 방향',
    body: '입안에서 자극이 강한 술보다 둥글고\n편안한 질감을 더 잘 받아들이는 편이에요.',
  ),
  LetterMeaning(
    letter: oliveLetter,
    title: '은은하게 남는 방향',
    body: '과하게 튀는 향보다 잔잔하게 남는 향과\n부드러운 여운에서 만족감을 느끼는 편이에요.',
  ),
];
