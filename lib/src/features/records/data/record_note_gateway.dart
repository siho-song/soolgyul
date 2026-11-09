/// The one-line note a signed-in user adds to a record from its card, after
/// the record exists. It is optional and replaces what the record held.
abstract interface class RecordNoteGateway {
  /// The record's note; blank when it has none.
  Future<String> loadNote(String recordId);

  /// Stores [note] on the record; blank clears it.
  Future<void> saveNote({required String recordId, required String note});
}

class RecordNoteException implements Exception {
  const RecordNoteException(this.message);
  final String message;

  @override
  String toString() => message;
}
