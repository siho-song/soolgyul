/// The finish asks only what the drinking pages cannot: how long the finish
/// ran, whether the mouth cleared, and what came up the nose after swallowing
/// (2026-11-06). [label] is the published sentence the answer means; [chip] is
/// what the two-column chip says for it. Liked options come first, and within
/// each side the axes run length, clearing, nose.
enum FinishOption {
  pleasantLength('향이나 맛이 기분 좋게 이어졌어요', '✨ 길고 은은한 여운', true, 'length'),
  clean('입안이 금방 깔끔해져서 좋았어요', '🍃 싹 정리되는 깔끔함', true, 'clean'),
  aromaEcho('삼킨 뒤 코끝으로 향이 올라와서 좋았어요', '🌸 코끝으로 올라오는 잔향', true, 'aroma'),
  tooShort('향이나 맛이 너무 빨리 사라졌어요', '⏳ 여운 없이 뚝 끊김', false, 'length'),
  heavy('텁텁하고 무거운 느낌이 남아서 부담스러웠어요', '🍂 입안에 텁텁하게 남음', false, 'clean'),
  offFlavor('삼킨 뒤 잡미나 거슬리는 냄새가 올라왔어요', '🤢 잡미나 거슬리는 냄새', false, 'aroma');

  const FinishOption(this.label, this.chip, this.positive, this.family);
  final String label;
  final String chip;
  final bool positive;
  final String family;
}

/// What the finish page asks; every option stays selectable.
class FinishQuestion {
  static const title = '술을 삼킨 뒤, 여운은 어땠나요?';
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
