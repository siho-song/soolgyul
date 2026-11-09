import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../core/format/dates.dart';
import '../../taste_card/data/taste_card_snapshot_view_data.dart'
    show TasteCardTagKind;

class HistoryDay {
  const HistoryDay(
    this.text,
    this.rings, {
    this.date,
    this.muted = false,
    this.selected = false,
  });

  final String text;
  final List<Color> rings;

  /// The cell's day in the shown month; `null` for adjacent-month padding.
  final DateTime? date;
  final bool muted;
  final bool selected;
}

/// Whether [a] and [b] fall on the same calendar day.
bool historySameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// One saved record of the signed-in account, as the 취향 tab lists it.
class HistoryRecord {
  const HistoryRecord({
    required this.resultId,
    required this.title,
    required this.categoryKey,
    required this.categoryLabel,
    required this.recordedAt,
    this.tags = const <HistoryTag>[],
    this.summary,
    this.note,
    this.imageUrl,
  });

  /// The card's id; tapping the record opens this card.
  final String resultId;
  final String title;
  final String? categoryKey;
  final String categoryLabel;

  /// Local time of the record.
  final DateTime recordedAt;

  /// The card's 핵심 요약 tags.
  final List<HistoryTag> tags;

  /// The card's one line for a record: its brief, or on a card made before
  /// the brief its long line as plain text; `null` when the card has none.
  final String? summary;

  /// The reader's one-line note; `null` without one.
  final String? note;

  /// Public catalog photo of the bottle; `null` without one.
  final String? imageUrl;

  Color get color => historyCategoryColor(categoryKey);

  /// '와인 · 2026.06.18 8:10 PM'
  String get meta {
    final hour = recordedAt.hour % 12 == 0 ? 12 : recordedAt.hour % 12;
    final minute = recordedAt.minute.toString().padLeft(2, '0');
    final period = recordedAt.hour < 12 ? 'AM' : 'PM';
    return '$categoryLabel · ${formatDotDate(recordedAt)} '
        '$hour:$minute $period';
  }
}

/// One 핵심 요약 tag of a card: the sensation and which way it went.
class HistoryTag {
  const HistoryTag(this.label, this.kind);

  final String label;
  final TasteCardTagKind kind;
}

/// The month in one plain line: how many glasses, which kind most, and
/// the sensation the reader liked more than once.
///
/// '11월엔 다섯 잔, 와인을 가장 많이 마셨고 산미를 특히 좋아했어요.'
String historyMonthSummaryLine(
  DateTime month,
  List<HistoryRecord> records, {
  required DateTime today,
}) {
  final m = '${month.month}월엔';
  if (records.isEmpty) {
    final current = month.year == today.year && month.month == today.month;
    return current ? '$m 아직 남긴 술결이 없어요.' : '$m 남긴 술결이 없어요.';
  }
  if (records.length == 1) {
    return '$m ${records.single.categoryLabel} 한 잔을 마셨어요.';
  }

  final kinds = _ranked(<String>[for (final r in records) r.categoryLabel]);
  final top = kinds.first.value;
  final tied = kinds.where((e) => e.value == top).map((e) => e.key).toList();
  // The drinking, up to its verb's stem: 마셨어요 alone, 마셨고 before more.
  final String drank;
  if (kinds.length == 1) {
    drank = '${kinds.single.key}만 마셨';
  } else if (tied.length == 1) {
    drank = '${_withObject(tied.single)} 가장 많이 마셨';
  } else if (tied.length == 2) {
    drank = '${_withAnd(tied[0])} ${_withObject(tied[1])} 고루 마셨';
  } else {
    drank = '여러 술을 고루 마셨';
  }

  final liked = _leader(<String>[
    for (final record in records)
      for (final tag in record.tags)
        if (tag.kind == TasteCardTagKind.liked) tag.label,
  ], atLeast: 2);
  final glasses = _glasses(records.length);
  return liked == null
      ? '$m $glasses, $drank어요.'
      : '$m $glasses, $drank고 ${_withObject(liked)} 특히 좋아했어요.';
}

/// The value that occurs most, when it occurs [atLeast] times and leads
/// alone; `null` otherwise.
String? _leader(List<String> values, {required int atLeast}) {
  if (values.isEmpty) return null;
  final ranked = _ranked(values);
  if (ranked.first.value < atLeast) return null;
  if (ranked.length > 1 && ranked[1].value == ranked.first.value) return null;
  return ranked.first.key;
}

List<MapEntry<String, int>> _ranked(List<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts.update(value, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// '한 잔' … '열 잔', then '11잔'.
String _glasses(int count) {
  const words = ['', '한', '두', '세', '네', '다섯', '여섯', '일곱', '여덟', '아홉', '열'];
  return count < words.length ? '${words[count]} 잔' : '$count잔';
}

bool _endsClosed(String word) {
  final last = word.isEmpty ? 0 : word.codeUnitAt(word.length - 1);
  return last >= 0xAC00 && last <= 0xD7A3 && (last - 0xAC00) % 28 != 0;
}

String _withObject(String word) => '$word${_endsClosed(word) ? '을' : '를'}';
String _withAnd(String word) => '$word${_endsClosed(word) ? '과' : '와'}';

/// The calendar's mark colour for a category key.
Color historyCategoryColor(String? categoryKey) => switch (categoryKey) {
  'wine' => AppDataColors.wine,
  'whisky' => AppDataColors.whisky,
  'sake' => AppDataColors.sake,
  'korean_traditional' => AppDataColors.traditional,
  _ => AppDataColors.other,
};

/// Calendar cells for [month], padded to whole weeks with adjacent-month
/// days. A day carries one mark per record, in record order; [selected]
/// is highlighted.
List<HistoryDay> historyMonthDays(
  DateTime month,
  List<HistoryRecord> records, {
  DateTime? selected,
}) {
  final firstDay = DateTime(month.year, month.month);
  final daysBefore = firstDay.weekday % DateTime.daysPerWeek;
  final gridStart = DateTime(month.year, month.month, 1 - daysBefore);
  final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
  final cellCount = ((daysBefore + daysInMonth + 6) ~/ 7) * 7;
  final marks = <int, List<Color>>{};
  for (final record in records) {
    final at = record.recordedAt;
    if (at.year != month.year || at.month != month.month) continue;
    (marks[at.day] ??= <Color>[]).add(record.color);
  }
  return List<HistoryDay>.generate(cellCount, (index) {
    final date = DateTime(
      gridStart.year,
      gridStart.month,
      gridStart.day + index,
    );
    final inMonth = date.month == month.month;
    return HistoryDay(
      '${date.day}',
      inMonth ? marks[date.day] ?? const <Color>[] : const <Color>[],
      date: inMonth ? date : null,
      muted: !inMonth,
      selected: inMonth && selected != null && historySameDay(date, selected),
    );
  });
}

/// Read side of the 취향 tab: the account's saved records of one month.
abstract interface class PreferenceHistoryGateway {
  /// Records of [month], oldest first.
  Future<List<HistoryRecord>> loadMonth(DateTime month);

  /// When the newest record was saved; `null` without any record.
  Future<DateTime?> latestRecordedAt();
}
