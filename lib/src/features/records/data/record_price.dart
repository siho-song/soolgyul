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

/// Where a record's drink was bought.
enum RecordPurchasePlace {
  convenienceMart('convenience_mart', '편의점·마트'),
  smartOrderShop('smart_order_shop', '스마트오더·샵'),
  restaurantPub('restaurant_pub', '식당·주점'),
  bar('bar', '바'),
  dutyFreeAbroad('duty_free_abroad', '면세·해외');

  const RecordPurchasePlace(this.key, this.label);

  /// The stored key.
  final String key;

  /// As the record shows it.
  final String label;

  /// Null for a key this app does not know, and for none.
  static RecordPurchasePlace? fromKey(Object? key) {
    for (final place in values) {
      if (place.key == key) return place;
    }
    return null;
  }
}

class RecordPrice {
  const RecordPrice({required this.amount, required this.unit, this.place});

  /// The bounds the server keeps a price within.
  static const minAmount = 1;
  static const maxAmount = 10000000;

  /// Whole won.
  final int amount;
  final RecordPriceUnit unit;

  /// Where it was bought; null when the record does not say.
  final RecordPurchasePlace? place;

  /// A stored price, or null when the amount or the unit is missing or
  /// unknown. The place is kept only with a price.
  static RecordPrice? fromStored(
    Object? amount,
    Object? unit, [
    Object? place,
  ]) {
    final parsedUnit = RecordPriceUnit.fromKey(unit);
    if (amount is! int || parsedUnit == null) return null;
    return RecordPrice(
      amount: amount,
      unit: parsedUnit,
      place: RecordPurchasePlace.fromKey(place),
    );
  }

  /// '38,000원 · 한 병'
  String get amountLine => '${formatWon(amount)}원 · ${unit.label}';

  /// '38,000원 · 한 병 · 바': the price and, when the record says, where.
  String get infoLine => switch (place) {
    final place? => '$amountLine · ${place.label}',
    null => amountLine,
  };

  /// '구매 정보 : 38,000원 · 한 병 · 바'
  String get line => '구매 정보 : $infoLine';

  @override
  bool operator ==(Object other) =>
      other is RecordPrice &&
      other.amount == amount &&
      other.unit == unit &&
      other.place == place;

  @override
  int get hashCode => Object.hash(amount, unit, place);
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

/// The price, and where it was paid, that a signed-in user notes on a
/// record from its card, after the record exists. It is optional and
/// replaces what the record held.
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
