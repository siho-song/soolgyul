import 'package:flutter/foundation.dart';

/// What the card's ⋮ menu asks the 테이스팅 노트 to open.
enum TasteCardNoteSlot { overall, price }

/// Carries a choice in the card's ⋮ menu, which sits in the app's header, to
/// the card screen below it: the screen turns to its 테이스팅 노트 tab and
/// opens the chosen part's sheet there, so a note or a price is written in
/// one place.
class TasteCardNoteOpener extends ChangeNotifier {
  TasteCardNoteSlot? _pending;

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
}
