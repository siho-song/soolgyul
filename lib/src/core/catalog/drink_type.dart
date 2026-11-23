import 'package:flutter/painting.dart';

import '../../design/app_tokens.dart';

/// 주종: the four kinds of drink the app records. Its server key, the name
/// the app shows it by and its colour are written here once; everything that
/// lists, filters or colours by 주종 reads them from here.
enum DrinkType {
  wine('wine', '와인', AppDataColors.wine),
  whisky('whisky', '위스키', AppDataColors.whisky),
  sake('sake', '사케', AppDataColors.sake),
  koreanTraditional('korean_traditional', '전통주', AppDataColors.traditional);

  const DrinkType(this.key, this.label, this.color);

  /// The key the server stores it by.
  final String key;

  /// As the app shows it.
  final String label;

  /// Its mark's colour, where drinks are told apart by colour.
  final Color color;

  /// The 주종 of a server key, or null for a key this app does not know.
  static DrinkType? fromKey(Object? key) {
    for (final type in values) {
      if (type.key == key) return type;
    }
    return null;
  }
}
