import 'taste_fit_verdict.dart';

abstract interface class TasteFitGateway {
  /// Judges catalog products, however many, against the signed-in reader's
  /// cards. Fails as a whole when any of them could not be judged.
  Future<TasteFitResponse> judge(List<String> productIds);
}

class TasteFitGatewayException implements Exception {
  const TasteFitGatewayException({this.code});

  /// The function's `error_code` when it answered with one.
  final String? code;
}
