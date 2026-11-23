import 'package:supabase_flutter/supabase_flutter.dart';

/// The `error_code` a server function answered a refusal with, or null when
/// it gave none (the network failed, or the function fell over).
String? serverErrorCode(FunctionException error) {
  final details = error.details;
  return details is Map && details['error_code'] is String
      ? details['error_code'] as String
      : null;
}
