part of 'taste_card_wire_parser.dart';

// 테이스팅 노트 (view.note) came after the card, and only draws what the
// card already holds another way.

/// Null for a card stored without a note, and for a note this app cannot
/// read: the card opens either way, without its second tab. A part left out
/// reads as nothing answered.
TasteCardNoteViewData? _parseNote(Object? value, String path) {
  if (value == null) return null;
  try {
    final object = _record(value, path);
    return TasteCardNoteViewData(
      originalName: _noteText(object['original_name']),
      facts: <TasteCardNoteFactViewData>[
        for (final (index, item) in _noteItems(object['facts'], '$path.facts'))
          _parseNoteFact(item, '$path.facts[$index]'),
      ],
      nose: _parseNoteGroups(object['nose'], '$path.nose'),
      balance: _parseNoteBalanceRows(object['balance'], '$path.balance'),
      texture: _parseNoteGroups(object['texture'], '$path.texture'),
      // Left out by a card stored before the palate asked its flavours.
      flavor: object['flavor'] == null
          ? null
          : _parseNoteGroups(object['flavor'], '$path.flavor'),
      // Left out by a card stored before the finish's gauges were rows.
      finishBalance: object['finish_balance'] == null
          ? null
          : _parseNoteBalanceRows(
              object['finish_balance'],
              '$path.finish_balance',
            ),
      finish: _parseNoteGroups(object['finish'], '$path.finish'),
      revisit: _noteText(object['revisit']),
      appearance: _parseNoteAppearance(
        object['appearance'],
        '$path.appearance',
      ),
      serving: _parseNoteServing(object['serving'], '$path.serving'),
      words: _parseNoteWords(object['words'], '$path.words'),
    );
  } on TasteCardWireException {
    return null;
  }
}

List<(int, Object?)> _noteItems(Object? value, String path) =>
    value == null ? const <(int, Object?)>[] : _indexed(value, path);

TasteCardNoteFactViewData _parseNoteFact(Object? value, String path) {
  final object = _record(value, path);
  return TasteCardNoteFactViewData(
    label: _nonEmpty(object['label'], '$path.label'),
    value: _nonEmpty(object['value'], '$path.value'),
  );
}

/// 향, 질감, 풍미 and 여운 alike: the server's groups, in its order.
List<TasteCardNoteGroupViewData> _parseNoteGroups(Object? value, String path) =>
    <TasteCardNoteGroupViewData>[
      for (final (index, item) in _noteItems(value, path))
        _parseNoteGroup(item, '$path[$index]'),
    ];

TasteCardNoteGroupViewData _parseNoteGroup(Object? value, String path) {
  final object = _record(value, path);
  return TasteCardNoteGroupViewData(
    label: _nonEmpty(object['label'], '$path.label'),
    marks: _parseNoteMarks(object['marks'], '$path.marks'),
  );
}

List<TasteCardNoteMarkViewData> _parseNoteMarks(Object? value, String path) =>
    <TasteCardNoteMarkViewData>[
      for (final (index, item) in _noteItems(value, path))
        _parseNoteMark(item, '$path[$index]'),
    ];

TasteCardNoteMarkViewData _parseNoteMark(Object? value, String path) {
  final object = _record(value, path);
  return TasteCardNoteMarkViewData(
    label: _nonEmpty(object['label'], '$path.label'),
    felt: _noteFelt(object['felt']),
  );
}

/// 맛 밸런스 and 여운 밸런스 alike: the server's rows, in its order.
List<TasteCardNoteBalanceViewData> _parseNoteBalanceRows(
  Object? value,
  String path,
) => <TasteCardNoteBalanceViewData>[
  for (final (index, item) in _noteItems(value, path))
    _parseNoteBalance(item, '$path[$index]'),
];

TasteCardNoteBalanceViewData _parseNoteBalance(Object? value, String path) {
  final object = _record(value, path);
  final mark = object['mark'];
  if (mark != null && (mark is! int || mark < 1 || mark > 5)) {
    _fail('level_mark_invalid', '$path.mark');
  }
  return TasteCardNoteBalanceViewData(
    key: _noteText(object['key']),
    label: _nonEmpty(object['label'], '$path.label'),
    mark: mark as int?,
    word: _noteText(object['word']),
    felt: object['felt'] == null ? null : _noteFelt(object['felt']),
    said: _noteText(object['said']),
    // A step this app cannot read is left out; the row stays.
    level: switch (object['level']) {
      final int level when level >= 1 && level <= 5 => level,
      _ => null,
    },
    // Ends this app cannot read are left out likewise.
    ends: switch (object['ends']) {
      [final String low, final String high]
          when low.trim().isNotEmpty && high.trim().isNotEmpty =>
        (low.trim(), high.trim()),
      _ => null,
    },
  );
}

/// A way of taking it added on the server later reads as noticed.
TasteCardNoteFelt _noteFelt(Object? value) => switch (value) {
  'liked' => TasteCardNoteFelt.liked,
  'less' => TasteCardNoteFelt.less,
  'more' => TasteCardNoteFelt.more,
  'burden' => TasteCardNoteFelt.burden,
  _ => TasteCardNoteFelt.noticed,
};

/// A line the sheet can do without: null unless it has something to say.
String? _noteText(Object? value) => switch (value) {
  final String text when text.trim().isNotEmpty => text.trim(),
  _ => null,
};

/// The fields of the tasting note a look's group may be saved under.
const _appearanceFields = <String>{'appearance', 'appearance_texture'};

/// 외관 and 음용 방식 came after the note. Null for a kind of drink that
/// has none and for one this app cannot read: the rest of the note stays.
TasteCardNoteAppearanceViewData? _parseNoteAppearance(
  Object? value,
  String path,
) {
  if (value == null) return null;
  try {
    final object = _record(value, path);
    final groups = <TasteCardNoteChoiceViewData>[
      for (final (index, item) in _indexed(object['groups'], '$path.groups'))
        ?_parseNoteGroupChoice(item, '$path.groups[$index]'),
    ];
    return groups.isEmpty
        ? null
        : TasteCardNoteAppearanceViewData(
            label: _nonEmpty(object['label'], '$path.label'),
            groups: groups,
          );
  } on TasteCardWireException {
    return null;
  }
}

/// Null for a group saved under a field this app does not know, and for
/// one with nothing to choose.
TasteCardNoteChoiceViewData? _parseNoteGroupChoice(Object? value, String path) {
  final object = _record(value, path);
  final field = _string(object['key'], '$path.key');
  final options = _parseNoteOptions(object['options'], '$path.options');
  // A key that is none of the options chooses nothing.
  final chosen = _noteText(object['chosen']);
  return !_appearanceFields.contains(field) || options.isEmpty
      ? null
      : TasteCardNoteChoiceViewData(
          field: field,
          label: _nonEmpty(object['label'], '$path.label'),
          prompt: _noteText(object['prompt']),
          options: options,
          chosenKey: options.any((option) => option.key == chosen)
              ? chosen
              : null,
        );
}

TasteCardNoteChoiceViewData? _parseNoteServing(Object? value, String path) {
  if (value == null) return null;
  try {
    final object = _record(value, path);
    final options = _parseNoteOptions(object['options'], '$path.options');
    return options.isEmpty
        ? null
        : TasteCardNoteChoiceViewData(
            field: 'serving',
            label: _nonEmpty(object['label'], '$path.label'),
            prompt: _noteText(object['prompt']),
            options: options,
          );
  } on TasteCardWireException {
    return null;
  }
}

List<TasteCardNoteOptionViewData> _parseNoteOptions(
  Object? value,
  String path,
) => <TasteCardNoteOptionViewData>[
  for (final (index, item) in _indexed(value, path))
    _parseNoteOption(item, '$path[$index]'),
];

final _swatchPattern = RegExp(r'^#[0-9a-fA-F]{6}$');

TasteCardNoteOptionViewData _parseNoteOption(Object? value, String path) {
  final object = _record(value, path);
  return TasteCardNoteOptionViewData(
    key: _nonEmpty(object['key'], '$path.key'),
    label: _nonEmpty(object['label'], '$path.label'),
    icon: _noteText(object['icon']),
    short: _noteText(object['short']),
    // '#9B1B30'; a colour written another way is left out.
    swatch: switch (object['swatch']) {
      final String hex when _swatchPattern.hasMatch(hex) =>
        0xFF000000 | int.parse(hex.substring(1), radix: 16),
      _ => null,
    },
  );
}

/// The words came after the note. Null for a card served without them and
/// for words this app cannot read: the note is drawn all the same, and its
/// answers cannot be corrected.
TasteCardNoteWordsViewData? _parseNoteWords(Object? value, String path) {
  if (value == null) return null;
  try {
    final object = _record(value, path);
    final groups = <TasteCardNoteWordGroupViewData>[
      for (final (index, item) in _indexed(object['groups'], '$path.groups'))
        ?_parseNoteWordGroup(item, '$path.groups[$index]'),
    ];
    if (groups.isEmpty) return null;
    return TasteCardNoteWordsViewData(
      groups: groups,
      revisit: <String, String>{
        for (final MapEntry(:key, :value) in _noteWordEntries(
          object['revisit'],
          '$path.revisit',
        ))
          key: _nonEmpty(value, '$path.revisit.$key'),
      },
    );
  } on TasteCardWireException {
    return null;
  }
}

/// The words of one kind by option id; none when the kind is left out.
Iterable<MapEntry<String, Object?>> _noteWordEntries(
  Object? value,
  String path,
) => value == null
    ? const <MapEntry<String, Object?>>[]
    : _record(value, path).entries;

/// Null for a group of a way of taking it this app does not know.
TasteCardNoteWordGroupViewData? _parseNoteWordGroup(
  Object? value,
  String path,
) {
  final object = _record(value, path);
  final felts = switch (object['felt']) {
    'liked' => const <TasteCardNoteFelt>{TasteCardNoteFelt.liked},
    'noticed' => const <TasteCardNoteFelt>{TasteCardNoteFelt.noticed},
    'missed' => const <TasteCardNoteFelt>{
      TasteCardNoteFelt.less,
      TasteCardNoteFelt.more,
      TasteCardNoteFelt.burden,
    },
    _ => null,
  };
  return felts == null
      ? null
      : TasteCardNoteWordGroupViewData(
          label: _nonEmpty(object['label'], '$path.label'),
          felts: felts,
        );
}
