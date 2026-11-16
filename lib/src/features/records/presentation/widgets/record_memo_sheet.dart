import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/app_sheet.dart';
import '../../../../widgets/app_text_field.dart';

/// The sheet a short memo of a record is written in: the record's one-line
/// note, the aroma memo of its tasting note. It stores the memo itself and
/// closes once [onSave] went through. A save that failed keeps it open,
/// what was written still in the field, with the reason under it.
class RecordMemoSheet extends StatefulWidget {
  const RecordMemoSheet({
    required this.title,
    required this.initial,
    required this.maxLength,
    required this.onSave,
    this.hintText,
    this.keyPrefix = 'taste-card-note',
    super.key,
  });

  final String title;
  final String initial;

  /// The server keeps at most this many characters.
  final int maxLength;
  final String? hintText;

  /// Starts the keys of the field (`-field`), the button (`-save`) and the
  /// reason of a failed save (`-failure`).
  final String keyPrefix;

  /// Stores the memo; answers what went wrong, or null once it is saved.
  final Future<String?> Function(String memo) onSave;

  @override
  State<RecordMemoSheet> createState() => _RecordMemoSheetState();
}

class _RecordMemoSheetState extends State<RecordMemoSheet>
    with FocusWhenSheetOpens {
  late final _controller = TextEditingController(text: widget.initial);
  bool _saving = false;
  String? _failure;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    final failure = await widget.onSave(_controller.text);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: appSheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSheetHeading(title: widget.title),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            key: ValueKey<String>('${widget.keyPrefix}-field'),
            controller: _controller,
            focusNode: sheetFocus,
            minLines: 1,
            maxLines: 3,
            maxLength: widget.maxLength,
            hintText: widget.hintText,
            hasError: _failure != null,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_failure != null) setState(() => _failure = null);
            },
            onFieldSubmitted: (_) => unawaited(_save()),
          ),
          if (_failure case final failure?) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              failure,
              key: ValueKey<String>('${widget.keyPrefix}-failure'),
              style: AppTextStyles.body.copyWith(
                color: AppColors.actionPrimary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          AppButton(
            key: ValueKey<String>('${widget.keyPrefix}-save'),
            label: '완료',
            onPressed: () => unawaited(_save()),
            isLoading: _saving,
            variant: AppButtonVariant.accent,
            size: AppButtonSize.sheet,
          ),
        ],
      ),
    );
  }
}
