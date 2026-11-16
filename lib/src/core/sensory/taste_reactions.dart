/// How the reader judged one aroma, taste or mouthfeel answer: it was liked
/// or it was not. There is no answer between.
enum TasteReaction {
  liked,
  disliked;

  /// The two sides a reason or target can belong to.
  static const sides = values;
}
