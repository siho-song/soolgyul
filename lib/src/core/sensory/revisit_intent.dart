/// The single judgment asked before the drink search in onboarding and
/// re-asked inside the sensory questionnaire for repeat records.
enum RevisitIntent { wantAgain, wouldAcceptAgain, doNotWantAgain, unsure }

/// What the revisit question asks and the answers it offers, as every place
/// that asks it writes them: the questionnaire, and the 테이스팅 노트 where
/// it is answered again.
class RevisitQuestion {
  static const title = '이 술, 다음에 또 마시고 싶나요?';
  static const options = <(RevisitIntent, String)>[
    (RevisitIntent.wantAgain, '꼭 다시 마시고 싶어요'),
    (RevisitIntent.wouldAcceptAgain, '무난하게 괜찮았어요'),
    (RevisitIntent.doNotWantAgain, '아니요, 다른 술을 마셔볼래요'),
  ];

  /// The record's first page asks it short, the answers on one line, with
  /// the drink's look asked under it.
  static const recordTitle = '재음용 의사';
  static const recordOptions = <(RevisitIntent, String)>[
    (RevisitIntent.wantAgain, '있음'),
    (RevisitIntent.wouldAcceptAgain, '애매해요'),
    (RevisitIntent.doNotWantAgain, '없음'),
  ];

  /// The answer the record's question stands on for [intent]. A question
  /// skipped stands on the middle one: the question offers no "don't know",
  /// so the note shows none.
  static RevisitIntent recordAnswer(RevisitIntent intent) =>
      intent == RevisitIntent.unsure ? RevisitIntent.wouldAcceptAgain : intent;

  /// [intent] in the record's short words.
  static String recordLabel(RevisitIntent intent) {
    final shown = recordAnswer(intent);
    return recordOptions.firstWhere((option) => option.$1 == shown).$2;
  }
}
