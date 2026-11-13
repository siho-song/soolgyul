/// What a bottle or a glass of a record's drink cost, in whole won.
enum RecordPriceUnit {
  bottle('한 병'),
  glass('한 잔');

  const RecordPriceUnit(this.label);

  /// '한 병' or '한 잔', as the record shows it.
  final String label;

  /// The stored key: `bottle` or `glass`; null for any other.
  static RecordPriceUnit? fromKey(Object? key) => switch (key) {
    'bottle' => RecordPriceUnit.bottle,
    'glass' => RecordPriceUnit.glass,
    _ => null,
  };
}

class RecordPrice {
  const RecordPrice({required this.amount, required this.unit});

  /// The bounds the server keeps a price within.
  static const minAmount = 1;
  static const maxAmount = 10000000;

  /// Whole won.
  final int amount;
  final RecordPriceUnit unit;

  /// A stored pair, or null when either half is missing or unknown.
  static RecordPrice? fromStored(Object? amount, Object? unit) {
    final parsedUnit = RecordPriceUnit.fromKey(unit);
    if (amount is! int || parsedUnit == null) return null;
    return RecordPrice(amount: amount, unit: parsedUnit);
  }

  /// '구입 가격 : 38,000원 · 한 병'
  String get line => '구입 가격 : ${formatWon(amount)}원 · ${unit.label}';

  @override
  bool operator ==(Object other) =>
      other is RecordPrice && other.amount == amount && other.unit == unit;

  @override
  int get hashCode => Object.hash(amount, unit);
}

/// 38000 as '38,000'.
String formatWon(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// The price a signed-in user notes on a record from its card, after the
/// record exists. It is optional and replaces what the record held.
abstract interface class RecordPriceGateway {
  /// The record's price; null when it has none.
  Future<RecordPrice?> loadPrice(String recordId);

  /// Stores [price] on the record; null removes it.
  Future<void> savePrice({required String recordId, RecordPrice? price});
}

class RecordPriceException implements Exception {
  const RecordPriceException(this.message);
  final String message;

  @override
  String toString() => message;
}
