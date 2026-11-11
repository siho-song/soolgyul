import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../async_shown.dart';

/// Where a reported error goes. Replaced in tests.
typedef ErrorSink = void Function(Object error, StackTrace stack, String where);

ErrorSink _sink = _printInDebug;

void _printInDebug(Object error, StackTrace stack, String where) {
  if (kDebugMode) debugPrint('[$where] $error');
}

/// Sends reports to [sink] until the returned function is called.
@visibleForTesting
void Function() captureErrorReports(ErrorSink sink) {
  final before = _sink;
  _sink = sink;
  return () => _sink = before;
}

/// The one place an unexpected failure is handed to, from the handlers that
/// catch what nothing else caught and from a `catch` that tells the member
/// and would otherwise drop the cause. [where] names the flow, never a
/// person or a record.
void reportError(Object error, StackTrace stack, {required String where}) {
  final cause = error is FailedSinceSignOut ? error.cause : error;
  if (!worthReporting(cause)) return;
  _sink(cause, stack, where);
}

/// A phone without a network, a member who closed a login and the app's own
/// worded refusals are ordinary; a report of each would bury the faults.
bool worthReporting(Object error) {
  if (error is TimeoutException) return false;
  if (error is AuthRetryableFetchException) return false;
  if (error is ServerFailure) return true;
  final type = error.runtimeType.toString();
  return !const <String>{
        'SocketException',
        'ClientException',
        'HandshakeException',
        'HttpException',
        'SocialAuthCancelledException',
      }.contains(type) &&
      !type.startsWith('_ClientSocketException');
}

/// The server answered with a fault of its own (5xx).
class ServerFailure implements Exception {
  const ServerFailure(this.status, this.method, this.route);

  final int status;
  final String method;

  /// The kind of call and its name, with nothing a member put in the path.
  final String route;

  /// `/storage/v1/object/<bucket>/<member>/<file>` becomes
  /// `/storage/v1/object`; `/rest/v1/rpc/<name>` and `/functions/v1/<name>`
  /// keep the name.
  static String routeOf(Uri url) {
    final parts = url.pathSegments;
    final isRpc = parts.length >= 4 && parts[0] == 'rest' && parts[2] == 'rpc';
    final keep = isRpc ? 4 : 3;
    return '/${parts.take(keep).join('/')}';
  }

  @override
  String toString() => 'ServerFailure($status $method $route)';
}

/// Cuts what a message may carry of a person: an address, a token, a long
/// run of text from a row.
String scrubbed(String text) {
  final cleaned = text
      .replaceAll(RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+'), '<email>')
      .replaceAll(RegExp(r'eyJ[\w-]+\.[\w-]+\.[\w-]+'), '<token>')
      .replaceAll(RegExp(r'[A-Za-z0-9_-]{40,}'), '<long>');
  return cleaned.length > 300 ? '${cleaned.substring(0, 300)}…' : cleaned;
}

/// Starts collecting errors and runs [start]. With a [dsn] they go to
/// Sentry; without one they are printed in a debug run and dropped in a
/// release, and the app behaves the same.
Future<void> runWithErrorReporting({
  required String dsn,
  required String environment,
  required FutureOr<void> Function() start,
}) async {
  if (dsn.isEmpty) {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      reportError(
        details.exception,
        details.stack ?? StackTrace.current,
        where: 'flutter',
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      reportError(error, stack, where: 'uncaught');
      return true;
    };
    await start();
    return;
  }
  _sink = (error, stack, where) {
    unawaited(
      Sentry.captureException(
        error,
        stackTrace: stack,
        withScope: (scope) => scope.setTag('where', where),
      ),
    );
  };
  // Sentry sets the two handlers itself.
  await SentryFlutter.init((options) {
    configureErrorCollection(options, dsn: dsn, environment: environment);
    options
      ..attachScreenshot = false
      ..attachViewHierarchy = false
      ..enableUserInteractionBreadcrumbs = false;
  }, appRunner: start);
}

/// What leaves the device and what does not, whichever platform sends it:
/// no personal data by default, no printed lines, no tracing, nothing
/// ordinary, and messages with addresses and tokens cut out.
@visibleForTesting
void configureErrorCollection(
  SentryOptions options, {
  required String dsn,
  required String environment,
}) {
  options
    ..dsn = dsn
    ..environment = environment
    ..sendDefaultPii = false
    ..enablePrintBreadcrumbs = false
    ..tracesSampleRate = 0
    ..beforeSend = (event, hint) {
      final thrown = event.throwable;
      if (thrown != null && !worthReporting(thrown)) return null;
      for (final exception in event.exceptions ?? const <SentryException>[]) {
        final value = exception.value;
        if (value != null) exception.value = scrubbed(value);
      }
      event.user = null;
      return event;
    };
}

/// Hands a failed load to [reportError]; the screen goes on showing its own
/// message and retry.
final class ErrorReportingObserver extends ProviderObserver {
  const ErrorReportingObserver();

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    reportError(
      error,
      stackTrace,
      where: 'load:${context.provider.name ?? context.provider.runtimeType}',
    );
  }
}
