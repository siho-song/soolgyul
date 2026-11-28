/// One step of a gauge: the term for it and, where the gauge has one, the
/// plain words that explain the term.
class GaugeLevel {
  const GaugeLevel({required this.term, this.hint});

  final String term;
  final String? hint;

  /// What the gauge's row says once the step is chosen: `드라이 · 산뜻한
  /// 기본 드라이`, or the term alone on a gauge without hints.
  String get label => hint == null ? term : '$term · $hint';
}

/// One axis asked on five steps, worded for a kind of drink: 당도 for wine,
/// 단맛 for whisky. The stored answer names the axis and the step,
/// never the words.
class SensoryGauge {
  SensoryGauge({
    required this.axis,
    required this.label,
    required List<GaugeLevel> levels,
    this.ends,
  }) : levels = List.unmodifiable(levels) {
    if (levels.length != steps) {
      throw FormatException('A gauge has $steps steps: $axis');
    }
  }

  static const steps = 5;

  final String axis;
  final String label;

  /// The five steps, from 1 to 5.
  final List<GaugeLevel> levels;

  /// The words under the bar's two ends, on an axis that runs between two
  /// characters and not from little to much.
  final (String low, String high)? ends;

  GaugeLevel levelAt(int level) => levels[level - 1];

  /// What a chosen step is called away from its bar, on the review page and
  /// the tasting note: `당도 · 드라이`.
  String chipLabel(int level) => '$label · ${levelAt(level).term}';
}

/// The gauges one drink is asked: those of 맛 (Step 2) and those of 여운
/// (Step 3).
class GaugeSet {
  GaugeSet({
    required List<SensoryGauge> palate,
    required List<SensoryGauge> finish,
  }) : palate = List.unmodifiable(palate),
       finish = List.unmodifiable(finish);

  final List<SensoryGauge> palate;
  final List<SensoryGauge> finish;

  /// The gauge of [axis]; null for an axis this drink is not asked.
  SensoryGauge? of(String axis) {
    for (final gauge in palate.followedBy(finish)) {
      if (gauge.axis == axis) return gauge;
    }
    return null;
  }
}

/// `catalog/sensory/gauge-definitions.json`: every kind's gauges and which
/// of them a style of the kind is shown. The server reads the same file.
class SensoryGaugeDefinitions {
  SensoryGaugeDefinitions.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 2) {
      throw const FormatException('Unsupported gauge definitions');
    }
    final kinds = <String, _GaugeKind>{
      for (final MapEntry(:key, :value) in (json['kinds'] as Map).entries)
        key as String: _GaugeKind.fromJson(value as Map),
    };
    final fallback = json['fallback'] as Map;
    final fallbackKind = kinds[fallback['kind']];
    if (fallbackKind == null) {
      throw const FormatException('Unknown fallback gauge kind');
    }
    final axes = (fallback['palate_axes'] as List).cast<String>();
    _kinds = kinds;
    _fallbackKind = fallbackKind;
    _fallback = GaugeSet(
      palate: [
        for (final axis in axes)
          fallbackKind.palate
              .firstWhere((entry) => entry.gauge.axis == axis)
              .gauge,
      ],
      finish: fallbackKind.finish,
    );
  }

  late final Map<String, _GaugeKind> _kinds;
  late final _GaugeKind _fallbackKind;
  late final GaugeSet _fallback;

  /// The gauges of a drink of [categoryKey] and [styleKey]. A style-bound
  /// gauge (타닌, 탄산감, 증류식 소주의 눈금) is shown only to its styles. A
  /// category without gauges of its own, or none, is asked the fallback set.
  GaugeSet forDrink(String? categoryKey, String? styleKey) {
    final kind = _kinds[categoryKey];
    if (kind == null) return _fallback;
    return GaugeSet(
      palate: [
        for (final entry in kind.palate)
          if (entry.shownTo(styleKey)) entry.gauge,
      ],
      finish: kind.finish,
    );
  }

  /// The gauge that gives [axis] its name and end words for a drink of
  /// [categoryKey], whether or not its style is asked it: the kind's own
  /// gauge of that axis, else the fallback kind's. Null for an axis no
  /// sheet has. A bottle's level on an axis its kind is not asked (a white
  /// wine's 탄닌) is drawn under this.
  SensoryGauge? gaugeNamed(String? categoryKey, String axis) =>
      _kinds[categoryKey]?.named(axis) ?? _fallbackKind.named(axis);
}

/// The gauges of a kind, each once by its axis, whatever style sees it.
extension on _GaugeKind {
  SensoryGauge? named(String axis) {
    for (final gauge in palate.map((entry) => entry.gauge).followedBy(finish)) {
      if (gauge.axis == axis) return gauge;
    }
    return null;
  }
}

class _GaugeKind {
  _GaugeKind.fromJson(Map json)
    : palate = [
        for (final raw in json['palate'] as List) _ShownGauge(raw as Map),
      ],
      finish = [
        for (final raw in json['finish'] as List) _readGauge(raw as Map),
      ];

  final List<_ShownGauge> palate;
  final List<SensoryGauge> finish;
}

/// A palate gauge and the styles it is shown to. Without a `show` rule it is
/// shown to every drink of its kind; `styles` names the only styles that see
/// it, `except_styles` the ones that do not (a distilled soju is asked as a
/// spirit, not on the gauges of a brewed drink).
class _ShownGauge {
  _ShownGauge(Map json)
    : gauge = _readGauge(json),
      _styles = _styleList(json, 'styles'),
      _exceptStyles = _styleList(json, 'except_styles'),
      _unknownStyle = switch (json['show']) {
        final Map show => show['unknown_style'] == true,
        _ => false,
      };

  final SensoryGauge gauge;
  final List<String>? _styles;
  final List<String>? _exceptStyles;
  final bool _unknownStyle;

  bool shownTo(String? styleKey) {
    final styles = _styles;
    if (styles != null) {
      return styleKey == null ? _unknownStyle : styles.contains(styleKey);
    }
    return !(_exceptStyles?.contains(styleKey) ?? false);
  }
}

List<String>? _styleList(Map json, String field) {
  final show = json['show'];
  final styles = show is Map ? show[field] : null;
  return styles is List ? styles.cast<String>() : null;
}

SensoryGauge _readGauge(Map json) => SensoryGauge(
  axis: _text(json, 'axis'),
  label: _text(json, 'label_ko'),
  ends: switch (json['ends_ko']) {
    [final String low, final String high] => (low, high),
    null => null,
    _ => throw FormatException('Invalid gauge ends: ${json['axis']}'),
  },
  levels: [
    for (final raw in json['levels'] as List)
      GaugeLevel(
        term: _text(raw as Map, 'term'),
        hint: raw['hint'] == null ? null : _text(raw, 'hint'),
      ),
  ],
);

String _text(Map row, String field) {
  final value = row[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing gauge $field');
  }
  return value;
}
