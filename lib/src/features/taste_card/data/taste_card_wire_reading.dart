part of 'taste_card_wire_parser.dart';

// Strict readers shared by the response parser. Each failure names its path.

const _alcoholCategories = <String>{
  'wine',
  'whisky',
  'korean_traditional',
  'sake',
};

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

void _exact(Map<String, Object?> value, Set<String> expected, String path) {
  if (value.keys.length != expected.length ||
      !value.keys.every(expected.contains)) {
    _fail('unexpected_fields', path);
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
