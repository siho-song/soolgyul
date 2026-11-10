import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/home/data/taste_letters.dart';

Map<String, dynamic> axisJson(String? letter, int left, int right, int votes) =>
    {
      'letter': letter,
      'left_share': left,
      'right_share': right,
      'vote_count': votes,
    };

void main() {
  group('TasteLettersState', () {
    final row = <String, dynamic>{
      'user_id': 'owner',
      'rule_version': 'v1',
      'record_count': 4,
      'updated_at': '2026-11-03T01:02:03Z',
      'axes': {
        'aroma': axisJson('F', 75, 25, 4),
        'sweetness': axisJson('D', 63, 37, 4),
        'weight': axisJson(null, 0, 0, 0),
        'finish': axisJson('C', 50, 50, 2),
      },
    };

    test('parses a full row', () {
      final state = TasteLettersState.fromRow(row);

      expect(state.recordCount, 4);
      expect(state.updatedAt, DateTime.utc(2026, 11, 3, 1, 2, 3).toLocal());
      expect(state.of(TasteLetterAxis.sweetness).letter, 'D');
      expect(state.of(TasteLetterAxis.sweetness).leftShare, 63);
      expect(state.of(TasteLetterAxis.sweetness).rightShare, 37);
      expect(state.of(TasteLetterAxis.sweetness).voteCount, 4);
      expect(state.of(TasteLetterAxis.weight).revealed, isFalse);
      expect(state.code, '산드·깔');
      expect(state.revealed, [
        TasteLetterAxis.aroma,
        TasteLetterAxis.sweetness,
        TasteLetterAxis.finish,
      ]);
      expect(state.hidden, [TasteLetterAxis.weight]);
    });

    test('words the overview and progress lines', () {
      final state = TasteLettersState.fromRow(row);

      expect(state.overviewStatement, '산뜻한 향이 감돌고 드라이하고 깔끔하게 마무리되는 술이 잘 맞아요.');
    });

    test('treats missing axes as empty', () {
      final state = TasteLettersState.fromRow({
        'record_count': 0,
        'axes': {'aroma': axisJson(null, 0, 0, 0)},
      });

      expect(state.code, '····');
      expect(state.revealed, isEmpty);
      expect(state.of(TasteLetterAxis.finish), TasteLetterAxisState.empty);
      expect(state.overviewStatement, '첫 술결을 남기면 내 취향 조각이 채워져요.');
      expect(state.updatedAt, isNull);
    });

    test('tolerates a row without axes', () {
      final state = TasteLettersState.fromRow({'record_count': '2'});

      expect(state.recordCount, 2);
      expect(state.code, '····');
    });
  });

  test('a letter this version does not know reads as not yet revealed', () {
    final state = TasteLettersState.fromRow(<String, dynamic>{
      'record_count': 4,
      'axes': {
        'aroma': axisJson('F', 75, 25, 4),
        'sweetness': axisJson('Z', 63, 37, 4),
      },
    });
    expect(state.revealed, [TasteLetterAxis.aroma]);
    expect(state.letterOf(TasteLetterAxis.sweetness), isNull);
    // What the detail screen draws for each revealed letter exists.
    for (final axis in state.revealed) {
      expect(TasteLetterPole.of(state.letterOf(axis)), isNotNull);
    }
  });

  group('TasteLetterChange', () {
    test('words a first reveal', () {
      final change = TasteLetterChange.fromRow({
        'axis': 'sweetness',
        'from_letter': null,
        'to_letter': 'D',
        'left_share': 100,
        'right_share': 0,
        'product_name': '글렌피딕 12년',
        'changed_at': '2026-10-02T12:00:00Z',
      })!;

      expect(change.isFirstReveal, isTrue);
      expect(change.axis, TasteLetterAxis.sweetness);
      expect(change.kindLabel, '첫 발견');
      expect(change.quote, '드라이한 맛 축이 처음 발견되었어요');
      expect(change.changedAt, DateTime.utc(2026, 10, 2, 12).toLocal());
    });

    test('words a flip with the right particle', () {
      final change = TasteLetterChange.fromRow({
        'axis': 'weight',
        'from_letter': 'L',
        'to_letter': 'H',
        'left_share': 40,
        'right_share': 60,
        'product_name': '라프로익 10년',
        'changed_at': '2026-10-20T12:00:00Z',
      })!;

      expect(change.isFirstReveal, isFalse);
      expect(change.kindLabel, '무게 변화');
      expect(change.quote, '묵직한 질감 취향으로 바뀌었어요');
      expect(change.leftShare, 40);
      expect(change.rightShare, 60);
    });

    test('skips rows with an unknown axis or no date', () {
      expect(
        TasteLetterChange.fromRow({
          'axis': 'texture',
          'to_letter': 'X',
          'changed_at': '2026-10-20T12:00:00Z',
        }),
        isNull,
      );
      expect(
        TasteLetterChange.fromRow({'axis': 'aroma', 'to_letter': 'F'}),
        isNull,
      );
    });
  });

  test('every letter has a pole and axes carry their closed-slot caption', () {
    for (final axis in TasteLetterAxis.values) {
      expect(TasteLetterPole.of(axis.leftLetter)?.letter, axis.leftLetter);
      expect(TasteLetterPole.of(axis.rightLetter)?.letter, axis.rightLetter);
    }
    expect(TasteLetterPole.of('F')!.label, '산뜻한 향');
    expect(TasteLetterPole.of(null), isNull);
    expect(TasteLetterAxis.weight.hiddenCaption, '바디감 (무게)');
    expect(TasteLetterAxis.fromKey('finish'), TasteLetterAxis.finish);
    expect(TasteLetterAxis.fromKey('other'), isNull);
  });
}
