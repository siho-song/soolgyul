import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../widgets/app_snack_bar.dart';
import '../../data/record_price.dart';
import 'record_price_sheet.dart';

/// The price of the record a saved card shows. The card's header line and
/// its ⋮ menu share one, so both show the same price and either opens the
/// sheet. It reads the price once when made.
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
  bool _loaded = false;
  bool _settled = false;
  bool _busy = false;
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
      _loaded = true;
      return true;
    } catch (_) {
      // Opening the sheet reads it again.
      return false;
    } finally {
      if (!_disposed) {
        _settled = true;
        notifyListeners();
      }
    }
  }

  /// Opens the sheet filled with the stored price and stores what 완료 chose.
  Future<void> edit(BuildContext context) async {
    if (_busy) return;
    _busy = true;
    try {
      if (!_loaded && !await _load()) {
        if (context.mounted) {
          showAppSnackBar(context, '구입 가격을 불러오지 못했어요. 다시 시도해 주세요.');
        }
        return;
      }
      if (!context.mounted) return;
      final choice = await showRecordPriceSheet(context, initial: _price);
      if (choice == null || choice.price == _price || _disposed) return;
      await gateway.savePrice(recordId: recordId, price: choice.price);
      if (_disposed) return;
      _price = choice.price;
      notifyListeners();
      onSaved?.call();
    } on RecordPriceException catch (error) {
      if (context.mounted) showAppSnackBar(context, error.message);
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(context, '구입 가격을 저장하지 못했어요. 다시 시도해 주세요.');
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
