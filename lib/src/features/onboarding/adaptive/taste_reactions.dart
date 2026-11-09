/// How the reader judged one aroma, taste or mouthfeel answer.
enum TasteReaction {
  liked,
  disliked,

  /// 적당했어요: evaluated, but neither liked nor a burden (2026-10-25). Only
  /// tastes and mouthfeel offer it; it takes no reason and no target.
  fine;

  /// The two sides a reason or target can belong to.
  static const sides = [liked, disliked];
}
