part of 'taste_card_wire_parser.dart';

// Readers shared by the response parser. Each failure names its path.

Map<String, Object?> _record(Object? value, String path) {
  if (value is! Map) {
    _fail('object_required', path);
  }
  try {
    return Map<String, Object?>.from(value);
  } on TypeError {
    _fail('object_required', path);
  }
}

/// Fails when a field the card is read from is missing. Fields the app
/// does not know are left alone: a server that adds one must not stop the
/// cards of an app installed before it from opening.
void _requireFields(
  Map<String, Object?> value,
  Set<String> required,
  String path,
) {
  if (!required.every(value.containsKey)) {
    _fail('missing_fields', path);
  }
}

String _string(Object? value, String path) {
  if (value is! String) {
    _fail('string_required', path);
  }
  return value;
}

String _nonEmpty(Object? value, String path) {
  final result = _string(value, path).trim();
  if (result.isEmpty) {
    _fail('non_empty_string_required', path);
  }
  return result;
}

String? _nullableNonEmpty(Object? value, String path) {
  return value == null ? null : _nonEmpty(value, path);
}

List<(int, Object?)> _indexed(Object? value, String path) {
  if (value is! List) {
    _fail('array_required', path);
  }
  return <(int, Object?)>[
    for (var index = 0; index < value.length; index++) (index, value[index]),
  ];
}

Duration? _durationMilliseconds(Object? value, String path) {
  if (value == null) {
    return null;
  }
  if (value is! int || value < 0) {
    _fail('non_negative_integer_required', path);
  }
  return Duration(milliseconds: value);
}

DateTime _timestamp(Object? value, String path) {
  final parsed = DateTime.tryParse(_nonEmpty(value, path));
  if (parsed == null) {
    _fail('timestamp_required', path);
  }
  return parsed.toUtc();
}

Never _fail(String code, String path) {
  throw TasteCardWireException(code, path);
}
