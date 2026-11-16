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

  static const all = <String>{
    appearance,
    appearanceTexture,
    serving,
    aromaMemo,
    palateMemo,
    finishMemo,
  };

  /// The server keeps at most this many characters of a section's memo.
  static const memoMaxLength = 200;
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
