/// The finish asks only what the drinking pages cannot: how long the finish
/// ran, whether the mouth cleared, and what came up the nose after swallowing
/// (2026-11-06). [chip] is what the two-column chip says. Liked options come
/// first, and within each side the axes run length, clearing, nose.
enum FinishOption {
  pleasantLength('✨ 은은하고 긴 여운', true, 'length'),
  clean('🍃 깔끔하고 정돈된 마무리', true, 'clean'),
  aromaEcho('🌸 코끝에 맴도는 잔향', true, 'aroma'),
  tooShort('⏳ 여운 없이 뚝 끊김', false, 'length'),
  heavy('🍂 입안에 텁텁하게 남음', false, 'clean'),
  offFlavor('🤢 거슬리는 잡미나 향', false, 'aroma');

  const FinishOption(this.chip, this.positive, this.family);
  final String chip;
  final bool positive;
  final String family;
}

/// What the finish page asks; every option stays selectable.
class FinishQuestion {
  static const title = '마신 뒤 입안에 남는 여운은 어땠나요?';
  static const hint = '기억에 남는 마무리를 가볍게 골라보세요.';
}

class FinishSelection {
  final Set<FinishOption> _selected = {};
  bool _unsure = false;
  Set<FinishOption> get selected => Set.unmodifiable(_selected);
  bool get unsure => _unsure;
  void toggle(FinishOption option) {
    _unsure = false;
    if (!_selected.remove(option)) _selected.add(option);
  }

  void toggleUnsure() {
    _unsure = !_unsure;
    if (_unsure) _selected.clear();
  }
}
