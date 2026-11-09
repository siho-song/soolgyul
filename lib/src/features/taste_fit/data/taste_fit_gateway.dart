import 'taste_fit_verdict.dart';

abstract interface class TasteFitGateway {
  /// Judges up to 20 catalog products against the signed-in reader's cards.
  Future<TasteFitResponse> judge(List<String> productIds);
}

class TasteFitGatewayException implements Exception {
  const TasteFitGatewayException({this.code});

  /// The function's `error_code` when it answered with one.
  final String? code;
}
