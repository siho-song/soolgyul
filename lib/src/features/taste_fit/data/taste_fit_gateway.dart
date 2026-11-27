import '../../../core/errors/connection_failure.dart';
import 'taste_fit_verdict.dart';

abstract interface class TasteFitGateway {
  /// Judges catalog products, however many, against the signed-in reader's
  /// cards. Fails as a whole when any of them could not be judged.
  Future<TasteFitResponse> judge(List<String> productIds);
}

class TasteFitGatewayException implements Exception, RewordedFailure {
  const TasteFitGatewayException({this.code, this.cause});

  /// The function's `error_code` when it answered with one.
  final String? code;

  /// What the call failed with, when it was not a refusal with a [code].
  @override
  final Object? cause;
}
