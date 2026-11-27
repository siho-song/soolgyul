import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/tasting_note_gateway.dart';
import '../../../../widgets/failure_words.dart';

/// What the member entered on the 테이스팅 노트 tab of the record a saved
/// card shows: the look, the way it was drunk, the occasion. It reads them
/// once when made; the note's form keeps its changes at once on 완료.
class TastingNoteEditor extends ChangeNotifier {
  TastingNoteEditor({required this.recordId, required this.gateway}) {
    unawaited(_load());
  }

  final String recordId;
  final TastingNoteGateway gateway;

  /// What the server holds, as far as it has answered.
  final _stored = <String, String>{};

  /// What the sheet shows: the stored entries.
  final _shown = <String, String>{};

  /// The read on its way, so a change made meanwhile waits for that one.
  Future<bool>? _reading;
  bool _loaded = false;
  bool _disposed = false;

  /// The entry of [field] (a [TastingNoteField]); null with nothing entered
  /// or before the entries have been read.
  String? valueOf(String field) => _shown[field];

  /// The ways it was drunk ([TastingNoteField.serving]), as chosen; none
  /// with nothing entered.
  List<String> get servings => switch (_shown[TastingNoteField.serving]) {
    final String ways => ways.split(TastingNoteField.servingSeparator),
    null => const <String>[],
  };

  /// The memo of a section ([TastingNoteField.aromaMemo] and the like);
  /// blank without one.
  String memoOf(String field) => _shown[field] ?? '';

  /// Whether the entries have been read, so a blank one is known to be
  /// blank.
  bool get settled => _loaded;

  Future<bool> _load() =>
      _reading ??= _read().whenComplete(() => _reading = null);

  /// What the last read failed with; null when it went through.
  Object? _loadError;

  Future<bool> _read() async {
    try {
      final entries = await gateway.load(recordId);
      if (_disposed) return false;
      _stored
        ..clear()
        ..addAll(entries);
      _shown
        ..clear()
        ..addAll(entries);
      _loaded = true;
      _loadError = null;
      notifyListeners();
      return true;
    } catch (error) {
      // The next change reads them again.
      _loadError = error;
      return false;
    }
  }

  /// Stores every field of [patch] at once, a null clearing its field.
  /// Returns what went wrong, with the entries as the server has them, or
  /// null.
  Future<String?> saveAll(Map<String, String?> patch) async {
    if (_disposed || patch.isEmpty) return null;
    if (!_loaded && !await _load()) {
      return failureLine(_loadError, '테이스팅 노트를 불러오지 못했어요. 다시 시도해 주세요.');
    }
    try {
      await gateway.save(recordId, patch);
    } on TastingNoteException catch (error) {
      return error.message;
    } catch (error) {
      return failureLine(error, '테이스팅 노트를 저장하지 못했어요. 다시 시도해 주세요.');
    }
    if (_disposed) return null;
    for (final MapEntry(:key, :value) in patch.entries) {
      _put(_stored, key, value);
      _put(_shown, key, value);
    }
    notifyListeners();
    return null;
  }

  static void _put(Map<String, String> entries, String field, String? value) {
    if (value == null) {
      entries.remove(field);
    } else {
      entries[field] = value;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
