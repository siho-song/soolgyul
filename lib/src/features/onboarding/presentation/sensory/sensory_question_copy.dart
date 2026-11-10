import '../../../../core/sensory/finish_choices.dart';
import '../../../../core/sensory/sensory_question_flow.dart';

/// 감각 질문 각 단계의 제목과 설명 문구입니다.
class SensoryQuestionCopy {
  const SensoryQuestionCopy(this.flow);

  final SensoryQuestionFlow flow;

  SensoryStep get _step => flow.current;

  String get title => switch (_step.page) {
    SensoryPage.revisit => '이 술, 다음에 또 마시고 싶나요?',
    // Only aromas have a notice page; they take their reaction there.
    SensoryPage.notice => '기억에 남거나 아쉬웠던 향이 있나요?',
    SensoryPage.reaction =>
      _step.section == SensorySection.taste
          ? '입안 가득 느껴진 맛은 어땠나요?'
          : '마실 때 입안의 감촉은 어땠나요?',
    SensoryPage.finish => FinishQuestion.title,
    // The flow leaves for the card on reaching this step; nothing is shown.
    SensoryPage.complete => '',
  };

  String get description => switch (_step.page) {
    SensoryPage.revisit => '솔직한 내 느낌을 가볍게 골라 보세요.',
    // The aroma page shows the tap guide capsules instead.
    SensoryPage.notice => '',
    SensoryPage.reaction =>
      _step.section == SensorySection.taste
          ? '와닿았던 맛을 골라 보세요.'
          : '기억에 남는 감각을 편하게 골라 보세요.',
    SensoryPage.finish => FinishQuestion.hint,
    // The flow leaves for the card on reaching this step; nothing is shown.
    SensoryPage.complete => '',
  };
}
