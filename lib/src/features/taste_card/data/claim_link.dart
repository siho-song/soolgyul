import 'taste_card_result.dart';

/// The ticket a card made on the web travels with into the app: the
/// result's pending conversion written into a link on the intro site.
///
/// A phone with the app opens the link in the app. Without the app the
/// link's page sends the visitor to the store, and on Android the ticket
/// rides along as the Play install referrer so the fresh install still
/// gets it. The app claims the ticket for the account once signed in.
///
/// The ticket is the whole right to the card, so it rides after the `#`:
/// that part of an address is never sent to the site's server, its logs or
/// the next page.
abstract final class TasteCardClaimLink {
  static const path = '/claim';

  static Uri build(String baseUrl, TasteCardPendingConversion ticket) =>
      Uri.parse(baseUrl).replace(
        path: path,
        fragment: Uri(queryParameters: _query(ticket)).query,
      );

  /// The ticket in a link to the intro site at [baseUrl], or `null` for
  /// any other link. A link with the app's own scheme or to another host
  /// is not a claim, whatever it carries: any page could write one.
  static TasteCardPendingConversion? parse(Uri uri, {required String baseUrl}) {
    final site = Uri.parse(baseUrl);
    final host = uri.host.toLowerCase();
    if (uri.scheme != site.scheme ||
        (host != site.host && host != 'www.${site.host}') ||
        (uri.path != path && uri.path != '$path/')) {
      return null;
    }
    return parseInstallReferrer(uri.fragment);
  }

  /// The ticket the Play store handed a fresh install (the link's part
  /// after the `#`), or `null`.
  static TasteCardPendingConversion? parseInstallReferrer(String? referrer) {
    if (referrer == null || referrer.isEmpty) return null;
    try {
      return _fromQuery(Uri.splitQueryString(referrer));
    } on ArgumentError {
      return null;
    } on FormatException {
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
