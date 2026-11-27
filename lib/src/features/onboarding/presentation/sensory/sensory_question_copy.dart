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

  String get title => switch (page) {
    SensoryPage.revisit => RevisitQuestion.title,
    SensoryPage.nose => '향(Aroma)',
    SensoryPage.palate => '맛과 질감(Palate)',
    SensoryPage.finish => '여운(Finish)',
    SensoryPage.review => '아쉬웠던 부분이 있으면 골라주세요.',
    // The flow leaves for the card on reaching this step; nothing is shown.
    SensoryPage.complete => '',
  };

  String get description => switch (page) {
    SensoryPage.revisit => '솔직한 내 느낌을 가볍게 골라 주세요.',
    SensoryPage.nose => '느낀 인상들을 골라 주세요.',
    SensoryPage.palate => '입안에서 느껴진 인상을 가볍게 선택해 주세요.',
    SensoryPage.finish => '목 넘김 뒤에 남은 느낌을 가볍게 선택해 주세요.',
    SensoryPage.review => '',
    SensoryPage.complete => '',
  };
}
