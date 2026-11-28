import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../widgets/app_sheet.dart';
import '../../../../widgets/app_snack_bar.dart';
import '../../data/record_note_gateway.dart';
import 'record_memo_sheet.dart';

/// The 총평 of the record a saved card shows, written on its tasting note;
/// the card's ⋮ menu leads there. The 기록 tab shows it too. It reads the
/// 총평 once when made.
class RecordMemoEditor extends ChangeNotifier {
  RecordMemoEditor({
    required this.recordId,
    required this.gateway,
    this.onSaved,
  }) {
    unawaited(load());
  }

  final String recordId;
  final RecordNoteGateway gateway;

  /// Called after a changed memo is stored, so lists showing it reload.
  final VoidCallback? onSaved;

  String? _memo;
  bool _disposed = false;

  /// The stored memo, blank without one; null until it has been read.
  String? get memo => _memo;

  /// What the last read failed with; null when it went through.
  Object? _loadError;

  /// Reads the memo again; false when it could not be read.
  Future<bool> load() async {
    try {
      final memo = (await gateway.loadNote(recordId)).trim();
      if (_disposed) return false;
      _memo = memo;
      _loadError = null;
      notifyListeners();
      return true;
    } catch (error) {
      // Choosing the memo reads it again.
      _loadError = error;
      return false;
    }
  }

  /// Opens the sheet, named [title], filled with the stored memo, reading
  /// it first when it has not been read. The sheet stays open while its memo is stored: it
  /// closes once the memo is saved, which a notice then says.
  Future<void> edit(BuildContext context, {String title = '총평'}) async {
    if (!context.mounted) return;
    if (_memo == null && !await load()) {
      if (context.mounted) {
        showAppSnackBar(context, failureLine(_loadError, _loadFailure));
      }
      return;
    }
    if (!context.mounted) return;
    var sheetOpen = true;
    await showAppSheet<void>(
      context: context,
      builder: (_) => RecordMemoSheet(
        title: title,
        initial: _memo ?? '',
        maxLength: 2000,
        hintText: '예) 첫맛은 강렬했는데 은은한 단맛이 남아 좋았어요.',
        onSave: (memo) async {
          final failure = await _save(context, memo);
          // A sheet closed while its memo was on the way cannot say so.
          if (failure != null && !sheetOpen && context.mounted) {
            showAppSnackBar(context, failure);
          }
          return failure;
        },
      ),
    );
    sheetOpen = false;
  }

  /// Stores [memo] and says it was saved; an unchanged memo is not sent.
  /// Returns what went wrong, or null.
  Future<String?> _save(BuildContext context, String memo) async {
    final trimmed = memo.trim();
    if (trimmed == (_memo ?? '')) return null;
    try {
      await gateway.saveNote(recordId: recordId, note: memo);
    } on RecordNoteException catch (error) {
      return error.message;
    } catch (error) {
      return failureLine(error, '총평을 저장하지 못했어요. 다시 시도해 주세요.');
    }
    if (_disposed) return null;
    _memo = trimmed;
    notifyListeners();
    onSaved?.call();
    if (context.mounted) {
      showAppSnackBar(
        context,
        trimmed.isEmpty ? '총평을 지웠어요.' : '총평을 저장했어요.',
        success: true,
      );
    }
    return null;
  }

  /// Stores [memo] without a sheet or a notice; an unchanged memo is not
  /// sent. Returns what went wrong, or null.
  Future<String?> saveText(String memo) async {
    final trimmed = memo.trim();
    if (trimmed == (_memo ?? '')) return null;
    try {
      await gateway.saveNote(recordId: recordId, note: trimmed);
    } on RecordNoteException catch (error) {
      return error.message;
    } catch (error) {
      return failureLine(error, '총평을 저장하지 못했어요. 다시 시도해 주세요.');
    }
    if (_disposed) return null;
    _memo = trimmed;
    notifyListeners();
    onSaved?.call();
    return null;
  }

  static const _loadFailure = '총평을 불러오지 못했어요. 다시 시도해 주세요.';

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
