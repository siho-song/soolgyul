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
    SensoryPage.notice => '좋았거나, 거슬렸던 향이 있나요?',
    SensoryPage.reaction =>
      _step.section == SensorySection.taste
          ? '입안에서 느껴진 맛은 어땠나요?'
          : '마실 때 입안의 감촉은 어땠나요?',
    SensoryPage.finish => FinishQuestion.title,
    SensoryPage.complete => '감각 기록을 마쳤어요',
  };

  String get description => switch (_step.page) {
    SensoryPage.revisit => '혀의 솔직한 반응을 골라주세요.',
    // The aroma page shows the tap guide capsules instead.
    SensoryPage.notice => '',
    SensoryPage.reaction =>
      _step.section == SensorySection.taste
          ? '내 입맛에 맞았던 느낌을 가볍게 골라보세요.'
          : '기억에 남는 느낌만 편하게 골라보세요.',
    SensoryPage.finish => FinishQuestion.hint,
    SensoryPage.complete => '다음으로 넘어가 메모를 남길 수 있어요.',
  };
}
