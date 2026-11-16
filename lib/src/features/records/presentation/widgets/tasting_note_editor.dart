import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../widgets/app_sheet.dart';
import '../../../../widgets/app_snack_bar.dart';
import '../../data/tasting_note_gateway.dart';
import 'record_memo_sheet.dart';

/// What the member entered on the 테이스팅 노트 tab of the record a saved
/// card shows: the look, the way it was drunk, a memo per section. It reads
/// them once when made. A choice shows at once and is stored behind it; one
/// that could not be stored goes back and says so.
class TastingNoteEditor extends ChangeNotifier {
  TastingNoteEditor({required this.recordId, required this.gateway}) {
    unawaited(_load());
  }

  final String recordId;
  final TastingNoteGateway gateway;

  /// What the server holds, as far as it has answered.
  final _stored = <String, String>{};

  /// What the sheet shows: the stored entries, with those on their way.
  final _shown = <String, String>{};

  /// The latest change of each field; an older one that fails leaves the
  /// newer one standing.
  final _latest = <String, int>{};

  /// Changes are sent one at a time in the order made, so the server ends
  /// on the last one.
  Future<void> _sending = Future<void>.value();

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
      notifyListeners();
      return true;
    } catch (_) {
      // The next change reads them again.
      return false;
    }
  }

  /// Whether the entries have been read, reading them now if not.
  Future<bool> _ready(BuildContext context) async {
    if (_loaded || await _load()) return true;
    if (context.mounted) {
      showAppSnackBar(context, '테이스팅 노트를 불러오지 못했어요. 다시 시도해 주세요.');
    }
    return false;
  }

  /// Chooses [option] for [field]; choosing the chosen one clears it.
  Future<void> choose(BuildContext context, String field, String option) async {
    if (!await _ready(context)) return;
    final failure = await _save(field, _shown[field] == option ? null : option);
    if (failure != null && context.mounted) showAppSnackBar(context, failure);
  }

  /// Keeps [ways] as the ways it was drunk; none clears them.
  Future<void> chooseServings(BuildContext context, List<String> ways) async {
    if (!await _ready(context)) return;
    final failure = await _save(
      TastingNoteField.serving,
      ways.isEmpty ? null : ways.join(TastingNoteField.servingSeparator),
    );
    if (failure != null && context.mounted) showAppSnackBar(context, failure);
  }

  /// Opens the sheet a section's memo is written in, under [title] and
  /// filled with the stored one. It closes once the memo is saved, which a
  /// notice then says.
  Future<void> editMemo(
    BuildContext context, {
    required String field,
    required String title,
    String? hintText,
  }) async {
    if (!await _ready(context) || !context.mounted) return;
    await showAppSheet<void>(
      context: context,
      builder: (_) => RecordMemoSheet(
        title: title,
        initial: memoOf(field),
        hintText: hintText,
        maxLength: TastingNoteField.memoMaxLength,
        keyPrefix: 'taste-card-section-memo',
        onSave: (memo) async {
          final trimmed = memo.trim();
          if (trimmed == memoOf(field)) return null;
          final failure = await _save(field, trimmed.isEmpty ? null : trimmed);
          if (failure == null && context.mounted) {
            showAppSnackBar(
              context,
              trimmed.isEmpty ? '메모를 지웠어요.' : '메모를 저장했어요.',
              success: true,
            );
          }
          return failure;
        },
      ),
    );
  }

  /// Shows [value] for [field] and stores it. Returns what went wrong,
  /// with the field back as the server has it, or null.
  Future<String?> _save(String field, String? value) async {
    if (_disposed || value == _shown[field]) return null;
    final change = _latest[field] = (_latest[field] ?? 0) + 1;
    _put(_shown, field, value);
    notifyListeners();
    final sent = _sending.then(
      (_) => gateway.save(recordId, <String, Object?>{field: value}),
    );
    _sending = sent.then<void>((_) {}, onError: (Object _) {});
    String failure;
    try {
      await sent;
      _put(_stored, field, value);
      return null;
    } on TastingNoteException catch (error) {
      failure = error.message;
    } catch (_) {
      failure = '테이스팅 노트를 저장하지 못했어요. 다시 시도해 주세요.';
    }
    if (!_disposed && _latest[field] == change) {
      _put(_shown, field, _stored[field]);
      notifyListeners();
    }
    return failure;
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
