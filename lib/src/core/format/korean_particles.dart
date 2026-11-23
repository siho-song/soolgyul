/// Whether a word's last syllable closes on a consonant (받침), which decides
/// the particle that follows it: 와인은 and 위스키는, 와인을 and 위스키를. A word
/// that does not end on a Hangul syllable is read as open.
bool endsOnConsonant(String word) {
  if (word.isEmpty) return false;
  final last = word.runes.last;
  return last >= 0xAC00 && last <= 0xD7A3 && (last - 0xAC00) % 28 != 0;
}
