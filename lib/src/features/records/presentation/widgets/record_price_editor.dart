import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/record_price.dart';
import '../../../../widgets/failure_words.dart';

/// The price, and where it was bought, of the record a saved card shows.
/// The card's header line and the 테이스팅 노트's form share one, so both
/// show the same. It reads them once when made.
class RecordPriceEditor extends ChangeNotifier {
  RecordPriceEditor({
    required this.recordId,
    required this.gateway,
    this.onSaved,
  }) {
    unawaited(_load());
  }

  final String recordId;
  final RecordPriceGateway gateway;

  /// Called after a changed price is stored, so lists showing it reload.
  final VoidCallback? onSaved;

  RecordPrice? _price;
  bool _settled = false;
  bool _disposed = false;

  /// The stored price; null without one or before it has been read.
  RecordPrice? get price => _price;

  /// Whether the first read has finished, read or failed: until then the
  /// card shows no price line, so a stored price never flashes as empty.
  bool get settled => _settled;

  Future<bool> _load() async {
    try {
      final price = await gateway.loadPrice(recordId);
      if (_disposed) return false;
      _price = price;
      return true;
    } catch (_) {
      return false;
    } finally {
      if (!_disposed) {
        _settled = true;
        notifyListeners();
      }
    }
  }

  /// Stores [amount] and [place] together; null clears each. Returns
  /// what went wrong, or null.
  Future<String?> save({int? amount, String? place}) async {
    final trimmed = place?.trim();
    final kept = trimmed == null || trimmed.isEmpty ? null : trimmed;
    if (_disposed || (amount == _price?.amount && kept == _price?.place)) {
      return null;
    }
    try {
      await gateway.save(recordId: recordId, amount: amount, place: kept);
    } on RecordPriceException catch (error) {
      return error.message;
    } catch (error) {
      return failureLine(error, '구매 정보를 저장하지 못했어요. 다시 시도해 주세요.');
    }
    if (_disposed) return null;
    _price = amount == null && kept == null
        ? null
        : RecordPrice(amount: amount, place: kept);
    notifyListeners();
    onSaved?.call();
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
