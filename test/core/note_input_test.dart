import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/format/note_input.dart';

void main() {
  final today = DateTime(2026, 11, 26);
  String? day(String input) => normalizeDay(input, today: today);

  test('a day is read from its digits or its parts', () {
    expect(day('200115'), '2020.01.15');
    expect(day('20200115'), '2020.01.15');
    expect(day('2020.1.5'), '2020.01.05');
    expect(day('2020-01-05'), '2020.01.05');
    expect(day('2020/1/5'), '2020.01.05');
    expect(day(' 2020.01.05 '), '2020.01.05');
    expect(day('2026.11.26'), '2026.11.26');
  });

  test('anything else is not a day', () {
    expect(day('어제'), isNull);
    expect(day('2020.13.01'), isNull);
    expect(day('2021.02.29'), isNull);
    expect(day('2026.11.27'), isNull, reason: 'a day still to come');
    expect(day('2020015'), isNull);
    expect(day('2020.01'), isNull);
    expect(day('abc'), isNull);
    expect(day(''), isNull);
  });

  test('a dotted day reads back as the date', () {
    expect(dayOfDot('2020.01.05'), DateTime(2020, 1, 5));
    expect(dotDay(DateTime(2020, 1, 5)), '2020.01.05');
  });

  test('a price keeps its digits, in whole won up to ten million', () {
    expect(parseWon('80,000'), 80000);
    expect(parseWon('80000원'), 80000);
    expect(parseWon('10,000,000'), 10000000);
    expect(parseWon('10,000,001'), isNull);
    expect(parseWon('0'), isNull);
    expect(parseWon(''), isNull);
    expect(groupWon(80000), '80,000');
    expect(groupWon(1), '1');
  });

  test('stars are read in halves from 0.5 to 5', () {
    expect(parseRating('3'), 3.0);
    expect(parseRating('3.0'), 3.0);
    expect(parseRating('3.50'), 3.5);
    expect(parseRating('.5'), .5);
    expect(parseRating(' 5 '), 5.0);
    for (final wrong in [
      '3.3',
      '6',
      '0',
      '5.5',
      'abc',
      '3..5',
      '3.5.',
      '',
      '-1',
    ]) {
      expect(parseRating(wrong), isNull, reason: wrong);
    }
  });
}
