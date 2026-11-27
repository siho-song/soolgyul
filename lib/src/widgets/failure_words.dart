import '../core/errors/connection_failure.dart';

/// How a failure of the connection is told, wherever it is told: the one
/// wording for a phone that is offline and a server that cannot be reached.
/// A screen hands the error it caught to `AppErrorView`, `AppCardError`,
/// [failureLine] or [failureWords], which choose between this and the
/// screen's own words.
abstract final class ConnectionFailureWords {
  static const title = '네트워크 연결이 불안정해요';
  static const description = '연결을 확인한 뒤 다시 시도해 주세요.';

  /// The two in one line, for a notice or a card.
  static const line = '$title. $description';
}

/// The one line that tells of a failure: the connection's wording when
/// [error] is a connection failure (core/errors/connection_failure.dart),
/// the screen's [own] line for any other failure or when there is no error
/// at hand.
String failureLine(Object? error, String own) =>
    isConnectionFailure(error) ? ConnectionFailureWords.line : own;

/// A failure told as a title over a line (a page, a popup): the
/// connection's wording for a connection failure, else the screen's own
/// [title] and [description].
({String title, String? description}) failureWords(
  Object? error, {
  required String title,
  String? description,
}) => isConnectionFailure(error)
    ? (
        title: ConnectionFailureWords.title,
        description: ConnectionFailureWords.description,
      )
    : (title: title, description: description);
