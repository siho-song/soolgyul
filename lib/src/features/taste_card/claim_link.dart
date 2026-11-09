import 'taste_card_result.dart';

/// The ticket a card made on the web travels with into the app: the
/// result's pending conversion written into a link on the intro site.
///
/// A phone with the app opens the link in the app. Without the app the
/// link's page sends the visitor to the store, and on Android the ticket
/// rides along as the Play install referrer so the fresh install still
/// gets it. The app claims the ticket for the account once signed in.
abstract final class TasteCardClaimLink {
  static const path = '/claim';

  static Uri build(String baseUrl, TasteCardPendingConversion ticket) =>
      Uri.parse(baseUrl).replace(path: path, queryParameters: _query(ticket));

  /// The ticket in a link, or `null` for any other link.
  static TasteCardPendingConversion? parse(Uri uri) =>
      uri.path == path ? _fromQuery(uri.queryParameters) : null;

  /// The ticket the Play store handed a fresh install, or `null`.
  static TasteCardPendingConversion? parseInstallReferrer(String? referrer) {
    if (referrer == null || referrer.isEmpty) return null;
    try {
      return _fromQuery(Uri.splitQueryString(referrer));
    } on ArgumentError {
      return null;
    }
  }

  static Map<String, String> _query(TasteCardPendingConversion ticket) =>
      <String, String>{
        's': ticket.anonymousSessionId,
        'r': ticket.resultId,
        'n': ticket.snapshotRef,
        't': ticket.conversionToken,
      };

  static TasteCardPendingConversion? _fromQuery(Map<String, String> query) {
    final session = query['s'];
    final result = query['r'];
    final snapshot = query['n'];
    final token = query['t'];
    if (session == null ||
        session.isEmpty ||
        result == null ||
        result.isEmpty ||
        snapshot == null ||
        snapshot.isEmpty ||
        token == null ||
        token.isEmpty) {
      return null;
    }
    return TasteCardPendingConversion(
      anonymousSessionId: session,
      resultId: result,
      snapshotRef: snapshot,
      conversionToken: token,
    );
  }
}
