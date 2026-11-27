import 'package:flutter/foundation.dart';

/// What the app's header asks the 테이스팅 노트 to open: the note in edit
/// mode (수정), or on a card with no note its 총평's sheet.
enum TasteCardNoteSlot { edit }

/// Carries the app header's 수정 and 완료 to the card screen below it, and
/// the screen's edit mode back to the header: while [editing] the header
/// shows 완료 in place of its menu, and leaving asks first when the form
/// holds unsaved changes ([dirty]).
class TasteCardNoteOpener extends ChangeNotifier {
  TasteCardNoteSlot? _pending;
  bool _editing = false;
  bool _dirty = false;
  Future<bool> Function()? _commit;

  /// Whether the note is in edit mode.
  bool get editing => _editing;

  /// Whether the form differs from what is stored.
  bool get dirty => _editing && _dirty;

  void open(TasteCardNoteSlot slot) {
    _pending = slot;
    notifyListeners();
  }

  /// The choice not handled yet; reading it clears it.
  TasteCardNoteSlot? take() {
    final slot = _pending;
    _pending = null;
    return slot;
  }

  /// The screen entered edit mode; [commit] saves the form and says
  /// whether it went through.
  void beginEditing(Future<bool> Function() commit) {
    _commit = commit;
    _editing = true;
    _dirty = false;
    notifyListeners();
  }

  /// The form changed, or came back to what is stored.
  void markDirty(bool dirty) {
    if (dirty == _dirty) return;
    _dirty = dirty;
    notifyListeners();
  }

  /// Leaves edit mode, whatever the form holds.
  void endEditing() {
    if (!_editing) return;
    _editing = false;
    _dirty = false;
    _commit = null;
    notifyListeners();
  }

  /// The back of edit mode, which the card screen answers: it asks first
  /// when the form holds changes, then leaves edit mode. Null outside it.
  Future<void> Function()? _back;

  /// Registers what the back of edit mode does.
  set onBack(Future<void> Function()? back) => _back = back;

  /// Back in edit mode: to the note only read, asking first when the form
  /// holds changes.
  Future<void> back() async => _back?.call();

  /// 완료: saves the form and, once saved, leaves edit mode.
  Future<bool> done() async {
    final commit = _commit;
    if (commit == null) return false;
    final saved = await commit();
    if (saved) endEditing();
    return saved;
  }
}
