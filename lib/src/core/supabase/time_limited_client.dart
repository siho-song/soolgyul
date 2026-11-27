import 'package:http/http.dart' as http;

import '../errors/connection_failure.dart';
import '../errors/error_report.dart';

/// Ends a request the network never answers, so the screen waiting on it
/// shows its error and a retry instead of loading without end, and names
/// every failure of the connection the same way: a [ConnectionFailure].
///
/// A table read gets the shortest limit, a photo upload the longest. The
/// database client would ask a failed read again on its own, up to four
/// times; a [ConnectionFailure] is not asked again, so the screen hears of
/// a dead connection after the first failure.
class TimeLimitedClient extends http.BaseClient {
  TimeLimitedClient({
    http.Client? inner,
    this.readLimit = defaultReadLimit,
    this.limit = const Duration(seconds: 20),
    this.uploadLimit = const Duration(seconds: 60),
  }) : _inner = inner ?? http.Client();

  /// How long a read waits for its answer.
  static const defaultReadLimit = Duration(seconds: 8);

  final http.Client _inner;
  final Duration readLimit;
  final Duration limit;
  final Duration uploadLimit;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isRead = request.method == 'GET' || request.method == 'HEAD';
    final isUpload = !isRead && request.url.path.contains('/storage/v1/object');
    final http.StreamedResponse response;
    try {
      response = await _inner
          .send(request)
          .timeout(
            isRead
                ? readLimit
                : isUpload
                ? uploadLimit
                : limit,
          );
    } catch (error, stack) {
      if (!isConnectionFailure(error)) rethrow;
      Error.throwWithStackTrace(ConnectionFailure(error), stack);
    }
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
