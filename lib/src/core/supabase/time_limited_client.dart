import 'package:http/http.dart' as http;

import '../errors/error_report.dart';

/// Ends a request the network never answers, so the screen waiting on it
/// shows its error and a retry instead of loading without end.
///
/// A table read gets the shortest limit: the database client asks a failed
/// read again on its own, up to four times, so its limit is spent four
/// times before the screen hears of it. A photo upload gets the longest.
class TimeLimitedClient extends http.BaseClient {
  TimeLimitedClient({
    http.Client? inner,
    this.readLimit = const Duration(seconds: 8),
    this.limit = const Duration(seconds: 20),
    this.uploadLimit = const Duration(seconds: 60),
  }) : _inner = inner ?? http.Client();

  final http.Client _inner;
  final Duration readLimit;
  final Duration limit;
  final Duration uploadLimit;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isRead = request.method == 'GET' || request.method == 'HEAD';
    final isUpload = !isRead && request.url.path.contains('/storage/v1/object');
    final response = await _inner
        .send(request)
        .timeout(
          isRead
              ? readLimit
              : isUpload
              ? uploadLimit
              : limit,
        );
    // Every request to the server passes here: a fault of the server's own
    // is noted once, whatever the screen then tells the member.
    if (response.statusCode >= 500) {
      reportError(
        ServerFailure(
          response.statusCode,
          request.method,
          ServerFailure.routeOf(request.url),
        ),
        StackTrace.current,
        where: 'server',
      );
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
