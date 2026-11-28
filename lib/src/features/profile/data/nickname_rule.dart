import 'package:flutter/services.dart';

/// A nickname: Korean, Latin letters and digits, with nothing between them.
final nicknamePattern = RegExp(r'^[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ]+$');

/// The dots the 천지인 keyboard writes on the way to a vowel: ㆍ ᆞ ᆢ · ‥.
const _vowelDots = 'ㆍᆞᆢ·‥';

/// Whether [name] holds a dot of a vowel still being typed.
final nicknameBeingTyped = RegExp('[$_vowelDots]');

/// What a nickname field lets in, typed or pasted: a nickname's letters and
/// the vowel dots. Dropping the dots would stop the vowel from being typed
/// at all; a name that still holds one is refused by [nicknamePattern] when
/// it is saved.
final nicknameInput = FilteringTextInputFormatter.allow(
  RegExp('[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ$_vowelDots]'),
);
