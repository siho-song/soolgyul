/// What a record's drink cost and where it was bought, as the member wrote
/// them on the 테이스팅 노트. Either may be missing.
class RecordPrice {
  const RecordPrice({this.amount, this.place})
    : assert(amount != null || place != null);

  /// The bounds the server keeps a price within.
  static const minAmount = 1;
  static const maxAmount = 10000000;

  /// The longest 구입처 the server keeps.
  static const placeMaxLength = 100;

  /// Whole won; null when only the place is written.
  final int? amount;

  /// Where it was bought, in the member's words; null when not written.
  final String? place;

  /// The places the app once offered as choices, stored by key: a record
  /// written then still reads in words.
  static const _placeKeys = <String, String>{
    'convenience_mart': '편의점·마트',
    'smart_order_shop': '스마트오더·샵',
    'restaurant_pub': '식당·주점',
    'bar': '바',
    'duty_free_abroad': '면세·해외',
  };

  /// A stored price and place, or null with neither.
  static RecordPrice? fromStored(Object? amount, Object? place) {
    final won = amount is int ? amount : null;
    final where = switch (place) {
      final String text when text.trim().isNotEmpty =>
        _placeKeys[text] ?? text.trim(),
      _ => null,
    };
    if (won == null && where == null) return null;
    return RecordPrice(amount: won, place: where);
  }

  /// '38,000원 · 와인샵': the price and, when written, where.
  String get infoLine => <String>[
    if (amount case final won?) '${formatWon(won)}원',
    ?place,
  ].join(' · ');

  /// '구매 정보 : 38,000원 · 와인샵'
  String get line => '구매 정보 : $infoLine';

  @override
  bool operator ==(Object other) =>
      other is RecordPrice && other.amount == amount && other.place == place;

  @override
  int get hashCode => Object.hash(amount, place);
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

/// The price, and where it was bought, that a signed-in user notes on a
/// record from its 테이스팅 노트, after the record exists. Each is optional.
abstract interface class RecordPriceGateway {
  /// The record's price; null when it has none.
  Future<RecordPrice?> loadPrice(String recordId);

  /// Stores [amount] as the record's price and [place] as where it was
  /// bought; a null clears each.
  Future<void> save({required String recordId, int? amount, String? place});
}

class RecordPriceException implements Exception {
  const RecordPriceException(this.message);
  final String message;

  @override
  String toString() => message;
}
