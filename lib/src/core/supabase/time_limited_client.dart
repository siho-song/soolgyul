import 'package:http/http.dart' as http;

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
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final isRead = request.method == 'GET' || request.method == 'HEAD';
    final isUpload = !isRead && request.url.path.contains('/storage/v1/object');
    return _inner
        .send(request)
        .timeout(
          isRead
              ? readLimit
              : isUpload
              ? uploadLimit
              : limit,
        );
  }

  @override
  void close() => _inner.close();
}
