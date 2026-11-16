import 'taste_card_result.dart';

/// What a saved record was answered with: the chosen option ids of each
/// question, by the question's key. A question left unanswered is left out.
class TasteCardAnswers {
  const TasteCardAnswers({required this.revisable, required this.answers});

  /// False for a record answered under an older questionnaire, whose
  /// answers cannot be corrected.
  final bool revisable;
  final Map<String, List<String>> answers;
}

/// The answers behind a saved card of the signed-in account: reading them,
/// and having the card written again from corrected ones.
abstract interface class TasteCardAnswersGateway {
  Future<TasteCardAnswers> loadAnswers(String resultId);

  /// Writes the card [resultId] again with the questions in [answers]
  /// answered anew, each by its chosen option ids; the server keeps the
  /// other questions as they are. The card keeps its id, its record and
  /// its date.
  Future<TasteCardResult> reviseAnswers(
    String resultId,
    Map<String, List<String>> answers,
  );

  /// The card as the server holds it now.
  Future<TasteCardResult> fetchOwnedResult(String resultId);
}
