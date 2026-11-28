import 'package:flutter/material.dart';

import '../../../core/catalog/drink_type.dart';
import '../../../design/app_tokens.dart';
import '../../../core/format/dates.dart';
import '../../records/data/record_price.dart';
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

/// One saved record of the signed-in account, as the 기록 tab lists it.
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
    this.price,
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

  /// The 구매 정보 the reader noted; `null` without one.
  final RecordPrice? price;

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

/// The calendar's mark colour for a category key.
Color historyCategoryColor(String? categoryKey) =>
    DrinkType.fromKey(categoryKey)?.color ?? AppDataColors.other;

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

/// Read side of the 기록 tab: the account's saved records of one month.
/// A history source that can also give back the copies the phone kept from
/// last time; `null` when there is none.
abstract interface class KeepsHistory {
  Future<List<HistoryRecord>?> keptMonth(DateTime month);
  Future<DateTime?> keptLatest();
}

abstract interface class PreferenceHistoryGateway {
  /// Records of [month], oldest first.
  Future<List<HistoryRecord>> loadMonth(DateTime month);

  /// Every record of the account, newest first, for 기록 검색.
  Future<List<HistoryRecord>> loadAll();

  /// When the newest record was saved; `null` without any record.
  Future<DateTime?> latestRecordedAt();
}
