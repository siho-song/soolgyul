import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_snapshot_view_data.dart'
    show TasteCardTagKind;
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';

void main() {
  final june = DateTime(2026, 6);
  final inJune = DateTime(2026, 6, 18);
  final later = DateTime(2026, 8, 2);

  HistoryRecord record(String kind, [List<HistoryTag> tags = const []]) =>
      HistoryRecord(
        resultId: '$kind-${tags.length}',
        title: kind,
        categoryKey: kind,
        categoryLabel: kind,
        recordedAt: DateTime(2026, 6, 3),
        tags: tags,
      );
  const acid = HistoryTag('산미', TasteCardTagKind.liked);
  const tannin = HistoryTag('떫은맛', TasteCardTagKind.less);

  String line(List<HistoryRecord> records, {DateTime? today}) =>
      historyMonthSummaryLine(june, records, today: today ?? inJune);

  test('the kind drunk most, then the sensation liked more than once', () {
    final records = [
      record('와인', [acid, tannin]),
      record('와인', [acid]),
      record('위스키', [tannin]),
    ];
    expect(line(records), '6월엔 세 잔, 와인을 가장 많이 마셨고 산미를 특히 좋아했어요.');
  });

  test('a sensation liked once, or tied, or only weighed is left out', () {
    expect(
      line([
        record('와인', [acid]),
        record('위스키'),
      ]),
      '6월엔 두 잔, 와인과 위스키를 고루 마셨어요.',
    );
    const berry = HistoryTag('베리향', TasteCardTagKind.liked);
    expect(
      line([
        record('와인', [acid, berry]),
        record('위스키', [acid, berry]),
      ]),
      '6월엔 두 잔, 와인과 위스키를 고루 마셨어요.',
    );
    expect(
      line([
        record('와인', [tannin]),
        record('와인', [tannin]),
        record('사케'),
      ]),
      '6월엔 세 잔, 와인을 가장 많이 마셨어요.',
    );
  });

  test('one kind only, two tied, three or more tied', () {
    expect(
      line([
        record('와인', [acid]),
        record('와인', [acid]),
      ]),
      '6월엔 두 잔, 와인만 마셨고 산미를 특히 좋아했어요.',
    );
    expect(
      line([
        record('와인', [acid]),
        record('사케', [acid]),
      ]),
      '6월엔 두 잔, 와인과 사케를 고루 마셨고 산미를 특히 좋아했어요.',
    );
    expect(
      line([record('와인'), record('위스키'), record('사케')]),
      '6월엔 세 잔, 여러 술을 고루 마셨어요.',
    );
  });

  test('one glass and none have their own lines', () {
    expect(line([record('위스키')]), '6월엔 위스키 한 잔을 마셨어요.');
    expect(line([]), '6월엔 아직 남긴 술결이 없어요.');
    expect(line([], today: later), '6월엔 남긴 술결이 없어요.');
  });

  test('counts above ten are digits', () {
    expect(
      line([...List.generate(11, (_) => record('와인')), record('사케')]),
      '6월엔 12잔, 와인을 가장 많이 마셨어요.',
    );
  });
}
