import '../../../../core/sensory/finish_choices.dart';
import '../../../../core/sensory/revisit_intent.dart';
import '../../../../core/sensory/sensory_question_flow.dart';

/// 감각 질문 각 단계의 제목과 설명 문구입니다.
class SensoryQuestionCopy {
  const SensoryQuestionCopy(this.flow);

  final SensoryQuestionFlow flow;

  SensoryStep get _step => flow.current;

  /// 맛 and 질감 are the two pages of one question, under one heading.
  static const palateTitle = '입안에서 느껴진 맛과 질감은 어땠나요?';

  String get title => switch (_step.page) {
    SensoryPage.revisit => RevisitQuestion.title,
    // Only aromas have a notice page; they take their reaction there.
    SensoryPage.notice => '잔에서 어떤 향이 느껴졌나요?',
    SensoryPage.reaction => palateTitle,
    SensoryPage.finish => FinishQuestion.title,
    // The flow leaves for the card on reaching this step; nothing is shown.
    SensoryPage.complete => '',
  };

  String get description => switch (_step.page) {
    SensoryPage.revisit => '솔직한 내 느낌을 가볍게 골라 보세요.',
    SensoryPage.notice => '코로 느낀 첫인상들을 골라 보세요.',
    SensoryPage.reaction => '입안에서 퍼지는 향도 함께 떠올려 보세요.',
    SensoryPage.finish => FinishQuestion.hint,
    // The flow leaves for the card on reaching this step; nothing is shown.
    SensoryPage.complete => '',
  };
}
