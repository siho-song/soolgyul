/// The fields of a record's tasting note that the member fills in on the
/// 테이스팅 노트 tab, by the name each is stored and saved under.
abstract final class TastingNoteField {
  static const appearance = 'appearance';
  static const appearanceTexture = 'appearance_texture';

  /// How it was drunk. One glass may be drunk several ways, so this one
  /// holds every way chosen, joined by [servingSeparator].
  static const serving = 'serving';
  static const servingSeparator = ',';
  static const aromaMemo = 'aroma_memo';
  static const palateMemo = 'palate_memo';
  static const finishMemo = 'finish_memo';

  /// The occasion, in the member's own words: what was eaten with it, and
  /// with whom and where it was drunk, in one line.
  static const pairing = 'pairing';

  /// The member's stars for the drink, 0.5 to 5 in halves, held as its
  /// number (4, 4.5).
  static const rating = 'rating';
  static const companionPlace = 'companion_place';

  /// When the bottle was bought, as `YYYY-MM-DD`.
  static const purchasedOn = 'purchased_on';

  static const all = <String>{
    appearance,
    appearanceTexture,
    serving,
    aromaMemo,
    palateMemo,
    finishMemo,
    pairing,
    rating,
    companionPlace,
    purchasedOn,
  };

  /// The server keeps at most this many characters of a section's memo.
  static const memoMaxLength = 200;

  /// The server keeps at most this many characters of an occasion's words.
  static const occasionMaxLength = 100;

  /// A stored date as a day; null for none or one not read.
  static DateTime? dayOf(String? stored) =>
      stored == null ? null : DateTime.tryParse(stored);

  /// A day as it is stored.
  static String storedDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

/// What a signed-in user adds to a record on its 테이스팅 노트 tab, after
/// the record exists: the things the questions do not ask. Each is
/// optional.
abstract interface class TastingNoteGateway {
  /// The record's entries by [TastingNoteField]; a field with nothing
  /// entered is left out.
  Future<Map<String, String>> load(String recordId);

  /// Stores the fields named in [patch] and leaves the others as they are;
  /// a null value clears its field.
  Future<void> save(String recordId, Map<String, Object?> patch);
}

class TastingNoteException implements Exception {
  const TastingNoteException(this.message);
  final String message;

  @override
  String toString() => message;
}
