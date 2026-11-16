import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/app_filter_chip.dart';
import '../../../../widgets/app_segments.dart';
import '../../../../widgets/app_sheet.dart';
import '../../data/record_price.dart';

/// What 완료 on the price sheet chose: a price, or none to remove it. A
/// dismissed sheet returns no choice at all.
typedef RecordPriceChoice = ({RecordPrice? price});

/// Opens the 구매 정보 sheet filled with [initial].
Future<RecordPriceChoice?> showRecordPriceSheet(
  BuildContext context, {
  RecordPrice? initial,
}) => showAppSheet<RecordPriceChoice>(
  context: context,
  builder: (context) => RecordPriceSheet(initial: initial),
);

/// The amount in whole won and 한 병 / 한 잔, then where it was bought, which
/// may be left unsaid. Cleared and 완료, the price goes, its place with it;
/// an amount outside what the server keeps is refused in the sheet.
class RecordPriceSheet extends StatefulWidget {
  const RecordPriceSheet({this.initial, super.key});

  final RecordPrice? initial;

  @override
  State<RecordPriceSheet> createState() => _RecordPriceSheetState();
}

class _RecordPriceSheetState extends State<RecordPriceSheet>
    with FocusWhenSheetOpens {
  late final _controller = TextEditingController(
    text: switch (widget.initial) {
      final price? => formatWon(price.amount),
      null => '',
    },
  );
  late var _unit = widget.initial?.unit ?? RecordPriceUnit.bottle;
  late var _place = widget.initial?.place;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    final digits = _controller.text.replaceAll(RegExp('[^0-9]'), '');
    if (digits.isEmpty) {
      Navigator.of(context).pop<RecordPriceChoice>((price: null));
      return;
    }
    final amount = int.parse(digits);
    if (amount < RecordPrice.minAmount || amount > RecordPrice.maxAmount) {
      setState(() => _error = '1원부터 1,000만 원까지 남길 수 있어요.');
      return;
    }
    Navigator.of(context).pop<RecordPriceChoice>((
      price: RecordPrice(amount: amount, unit: _unit, place: _place),
    ));
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    // On a short phone the sheet is taller than what the keyboard leaves.
    padding: appSheetPadding(context),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const AppSheetHeading(title: '구매 정보'),
        const SizedBox(height: AppSpacing.xl),
        _AmountField(
          controller: _controller,
          focusNode: sheetFocus,
          onChanged: () {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: _done,
        ),
        if (_error case final error?) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            error,
            key: const ValueKey<String>('record-price-error'),
            style: AppTextStyles.caption.copyWith(
              color: AppColors.actionDestructive,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        // 한 병 / 한 잔.
        AppSegments<RecordPriceUnit>(
          options: RecordPriceUnit.values,
          selected: _unit,
          label: (unit) => unit.label,
          segmentKey: (unit) =>
              ValueKey<String>('record-price-unit-${unit.name}'),
          onChanged: (unit) => setState(() => _unit = unit),
        ),
        const SizedBox(height: AppSpacing.xl),
        _PlaceChips(
          place: _place,
          // The chosen one, touched again, is left unsaid.
          onChanged: (place) =>
              setState(() => _place = place == _place ? null : place),
        ),
        const SizedBox(height: AppSpacing.xxl),
        AppButton(
          key: const ValueKey<String>('record-price-save'),
          label: '완료',
          onPressed: _done,
          variant: AppButtonVariant.accent,
          size: AppButtonSize.sheet,
        ),
      ],
    ),
  );
}

/// Digits only, shown with thousands separators. Nine digits at most, which
/// is past the largest price kept and stays a safe integer.
class _WonFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp('[^0-9]'), '');
    if (digits.isEmpty) return TextEditingValue.empty;
    if (digits.length > 9) return oldValue;
    final text = formatWon(int.parse(digits));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// No box: a 2px burgundy line under the number, which starts at the left
/// at the usual input size, with 원 right after it in a lighter grey.
class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  static const _number = AppTextStyles.amountInput;
  static final _won = AppTextStyles.body.copyWith(
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  /// Room after the last digit for the caret.
  static const _caretRoom = 14.0;

  /// Room kept at the line's end for 원.
  static const _wonRoom = 40.0;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(
        bottom: BorderSide(color: AppColors.actionPrimary, width: 2),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: 6),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  SizedBox(
                    width: _fieldWidth(context, value.text, constraints),
                    child: TextField(
                      key: const ValueKey<String>('record-price-field'),
                      controller: controller,
                      focusNode: focusNode,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: <TextInputFormatter>[_WonFormatter()],
                      onChanged: (_) => onChanged(),
                      onSubmitted: (_) => onSubmitted(),
                      style: _number,
                      cursorColor: AppColors.actionPrimary,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        hintText: '0',
                        hintStyle: _number.copyWith(
                          color: AppColors.controlInactive,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text('원', style: _won),
                ],
              ),
            ),
      ),
    ),
  );

  /// As wide as the number drawn in the field's own style, so 원 follows it.
  double _fieldWidth(
    BuildContext context,
    String text,
    BoxConstraints constraints,
  ) {
    final style = Theme.of(context).textTheme.bodyLarge!.merge(_number);
    final painter = TextPainter(
      text: TextSpan(text: text.isEmpty ? '0' : text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width + _caretRoom;
    painter.dispose();
    return width.clamp(0.0, constraints.maxWidth - _wonRoom);
  }
}

/// 구매처: where it was bought, one of five or none.
class _PlaceChips extends StatelessWidget {
  const _PlaceChips({required this.place, required this.onChanged});

  final RecordPurchasePlace? place;
  final ValueChanged<RecordPurchasePlace> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      const Text('구매처', style: AppTextStyles.sectionTitleSm),
      const SizedBox(height: AppSpacing.s10),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.s10,
        children: <Widget>[
          for (final option in RecordPurchasePlace.values)
            Semantics(
              button: true,
              selected: option == place,
              child: AppFilterChip(
                key: ValueKey<String>('record-price-place-${option.key}'),
                label: option.label,
                selected: option == place,
                onPressed: () => onChanged(option),
              ),
            ),
        ],
      ),
    ],
  );
}
