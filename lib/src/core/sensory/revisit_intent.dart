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
    (RevisitIntent.wouldAcceptAgain, '기회가 된다면 또 마실래요'),
    (RevisitIntent.doNotWantAgain, '아니요, 다른 술을 마셔볼래요'),
  ];
}
