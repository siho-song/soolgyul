import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';
import 'package:soolgyul/src/features/preferences/presentation/history/preference_history_daily_records.dart';
import 'package:soolgyul/src/features/records/data/record_price.dart';
import 'package:soolgyul/src/features/records/presentation/widgets/record_price_editor.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_more_action.dart';

import '../support/design_taste_card.dart';

const _recordId = '30000000-0000-4000-8000-000000000009';

class _Prices implements RecordPriceGateway {
  _Prices([this.stored]);

  RecordPrice? stored;
  final saves = <RecordPrice?>[];

  @override
  Future<RecordPrice?> loadPrice(String recordId) async {
    expect(recordId, _recordId);
    return stored;
  }

  @override
  Future<void> savePrice({required String recordId, RecordPrice? price}) async {
    expect(recordId, _recordId);
    saves.add(price);
    stored = price;
  }
}

/// The card with the ⋮ menu above it, sharing one price as the app does.
Future<RecordPriceEditor> _pumpCard(WidgetTester tester, _Prices prices) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final editor = RecordPriceEditor(recordId: _recordId, gateway: prices);
  addTearDown(editor.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        appBar: AppBar(
          actions: <Widget>[
            TasteCardMoreAction(recordId: _recordId, recordPrice: editor),
          ],
        ),
        body: TasteCardScreen(
          viewData: designTasteCard,
          onSave: () {},
          recordPrice: editor,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return editor;
}

final _priceLine = find.byKey(const ValueKey<String>('taste-card-price'));
final _field = find.byKey(const ValueKey<String>('record-price-field'));
final _save = find.byKey(const ValueKey<String>('record-price-save'));

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(_field).controller!.text;

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('taste-card-more')));
  await tester.pumpAndSettle();
}

HistoryRecord _record(String id, {RecordPrice? price}) => HistoryRecord(
  resultId: id,
  title: '테스트 리슬링',
  categoryKey: 'wine',
  categoryLabel: '와인',
  recordedAt: DateTime(2026, 11, 8, 20, 10),
  price: price,
);

void main() {
  test('a price reads with thousands separators and its unit', () {
    expect(formatWon(1), '1');
    expect(formatWon(38000), '38,000');
    expect(formatWon(10000000), '10,000,000');
    expect(
      const RecordPrice(amount: 38000, unit: RecordPriceUnit.glass).line,
      '구입 가격 : 38,000원 · 한 잔',
    );
    expect(RecordPrice.fromStored(38000, 'can'), isNull);
    expect(RecordPrice.fromStored(null, 'bottle'), isNull);
  });

  testWidgets('with no price the header offers + 입력, which adds one', (
    tester,
  ) async {
    final prices = _Prices();
    await _pumpCard(tester, prices);
    expect(find.text('구입 가격 : + 입력'), findsOneWidget);

    await tester.tap(_priceLine);
    await tester.pumpAndSettle();
    expect(find.text('구입 가격'), findsOneWidget);
    expect(_fieldText(tester), isEmpty);
    await tester.enterText(_field, '38000');
    await tester.pump();
    expect(_fieldText(tester), '38,000');
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(prices.saves, <RecordPrice?>[
      const RecordPrice(amount: 38000, unit: RecordPriceUnit.bottle),
    ]);
    expect(find.text('구입 가격 : 38,000원 · 한 병'), findsOneWidget);
    expect(find.text('구입 가격 : + 입력'), findsNothing);
  });

  testWidgets('the menu says 남기기 without a price and 수정 with one', (
    tester,
  ) async {
    await _pumpCard(tester, _Prices());
    await _openMenu(tester);
    expect(find.text('구입 가격 남기기'), findsOneWidget);
    expect(find.text('구입 가격 수정'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('taste-card-menu-price')));
    await tester.pumpAndSettle();
    await tester.enterText(_field, '12000');
    await tester.tap(_save);
    await tester.pumpAndSettle();

    await _openMenu(tester);
    expect(find.text('구입 가격 수정'), findsOneWidget);
    expect(find.text('구입 가격 남기기'), findsNothing);
  });

  testWidgets('the sheet opens filled, takes 한 잔, and cleared removes it', (
    tester,
  ) async {
    final prices = _Prices(
      const RecordPrice(amount: 38000, unit: RecordPriceUnit.bottle),
    );
    await _pumpCard(tester, prices);
    expect(find.text('구입 가격 : 38,000원 · 한 병'), findsOneWidget);

    await tester.tap(_priceLine);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The keyboard waits for the sheet to finish sliding up.
    EditableTextState editable() => tester.state<EditableTextState>(
      find.descendant(of: _field, matching: find.byType(EditableText)),
    );
    expect(editable().widget.focusNode.hasFocus, isFalse);
    await tester.pumpAndSettle();
    expect(editable().widget.focusNode.hasFocus, isTrue);
    expect(_fieldText(tester), '38,000');

    await tester.tap(
      find.byKey(const ValueKey<String>('record-price-unit-glass')),
    );
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(prices.saves.last, isNotNull);
    expect(prices.saves.last!.unit, RecordPriceUnit.glass);
    expect(find.text('구입 가격 : 38,000원 · 한 잔'), findsOneWidget);

    await tester.tap(_priceLine);
    await tester.pumpAndSettle();
    await tester.enterText(_field, '');
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(prices.saves.last, isNull);
    expect(find.text('구입 가격 : + 입력'), findsOneWidget);
  });

  testWidgets('an amount past what is kept is refused in the sheet', (
    tester,
  ) async {
    final prices = _Prices();
    await _pumpCard(tester, prices);
    await tester.tap(_priceLine);
    await tester.pumpAndSettle();

    for (final amount in <String>['20000000', '0']) {
      await tester.enterText(_field, amount);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('record-price-error')),
        findsOneWidget,
      );
    }
    expect(prices.saves, isEmpty);
    expect(_field, findsOneWidget);

    // Dismissed, the sheet leaves the record as it was.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(prices.saves, isEmpty);
  });

  testWidgets('the 취향 tab shows a price line only on a priced record', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: HistoryDayCard(
              title: '11월 8일',
              records: <HistoryRecord>[
                _record(
                  'a',
                  price: const RecordPrice(
                    amount: 38000,
                    unit: RecordPriceUnit.bottle,
                  ),
                ),
                _record('b'),
              ],
              onOpenCard: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('history-record-price-a')),
      findsOneWidget,
    );
    expect(find.text('구입 가격 : 38,000원 · 한 병'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('history-record-price-b')),
      findsNothing,
    );
    expect(find.textContaining('+ 입력'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
