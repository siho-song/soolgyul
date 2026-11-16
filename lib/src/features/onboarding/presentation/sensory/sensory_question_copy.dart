import '../../../../core/sensory/revisit_intent.dart';
import '../../../../core/sensory/sensory_question_flow.dart';

/// 감각 질문 각 단계의 제목과 설명 문구입니다. 첫 기록과 그 뒤의 기록이
/// 같은 문구를 씁니다.
class SensoryQuestionCopy {
  const SensoryQuestionCopy(this.page);

  final SensoryPage page;

  /// Over the aroma picker under the palate's gauges.
  static const palateFlavorTitle = '입안에서 느낀 향들을 선택해주세요.';

  /// Over the aroma picker under the finish's gauges.
  static const finishAromaTitle = '삼킨 뒤 느껴지는 향들을 선택해주세요.';

  /// Over the button of the last page that takes sensations, while the
  /// record holds none.
  static const sensationRequired = '향, 맛, 여운 중 하나 이상은 골라 주세요.';

  /// Over the short list of the drink's kind in those two pickers.
  static const frequentAromasTitle = '자주 느끼는 향';

  String get title => switch (page) {
    SensoryPage.revisit => RevisitQuestion.title,
    SensoryPage.nose => '잔에서 어떤 향이 느껴졌나요?',
    SensoryPage.palate => '입안에서 느껴진 맛과 질감은 어땠나요?',
    SensoryPage.finish => '삼킨 뒤 남는 여운은 어땠나요?',
    SensoryPage.review => '고르신 것들 중 아쉬웠던 부분이 있나요?',
    // The flow leaves for the card on reaching this step; nothing is shown.
    SensoryPage.complete => '',
  };

  String get description => switch (page) {
    SensoryPage.revisit => '솔직한 내 느낌을 가볍게 골라 보세요.',
    SensoryPage.nose => '코로 느낀 첫인상들을 골라 보세요.',
    SensoryPage.palate => '입안에서 느껴진 인상을 가볍게 선택해 보세요.',
    SensoryPage.finish => '목 넘김 뒤에 남은 느낌을 가볍게 선택해 보세요.',
    SensoryPage.review => '없다면 바로 저장을 눌러주세요 · 체크한 요소는 다음 추천에서 피해드려요',
    SensoryPage.complete => '',
  };
}
