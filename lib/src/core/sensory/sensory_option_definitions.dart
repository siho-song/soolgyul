import 'taste_reactions.dart';

enum AnswerPhase { overall, duringDrinking, afterSwallowing }

enum AnswerMeaning {
  noticed,
  evaluated,
  gentleIntensityAccepted,
  distinctIntensityAccepted,
  harmonious,
  excessiveIntensity,
  wantsMoreIntensity,
  masksOtherSensations,
  disharmonious,
  reasonUnknown,
  pleasantPersistence,
  quickClearing,
  tooBrief,
  heavyResidue,
  lingeringAroma,
  lingeringOffFlavor,
  revisitDesired,
  revisitAcceptable,
  revisitDeclined,
  unknown,
  reasonTargetSelected,

  /// 적당했어요: evaluated with no direction (2026-10-25).
  balanced,
}

/// Fixed choice data shared with the server; no answer interpretation happens here.
class ReasonDefinition {
  const ReasonDefinition({
    required this.key,
    required this.label,
    required this.meaning,
    required this.tasteMeanings,
    this.selectable = true,
  });

  final String key;
  final String label;
  final AnswerMeaning meaning;
  final Map<String, AnswerMeaning> tasteMeanings;

  /// Retired choices stay defined so previously saved answers remain readable.
  final bool selectable;

  AnswerMeaning meaningForTaste(String tasteKey) =>
      tasteMeanings[tasteKey] ?? meaning;
}

class MouthfeelDefinition {
  const MouthfeelDefinition({
    required this.key,
    required this.label,
    required this.axis,
    required this.axisLabel,
    required this.chipLabels,
  });

  final String key;
  final String label;
  final String axis;

  /// The row this choice sits on (무게감, 질감, 탄산, 열감).
  final String axisLabel;

  /// The direction chip under 좋았어요 or 아쉬웠어요 on a two-ended row
  /// (가벼워서, 묵직해서 …); a single sensation has none.
  final Map<TasteReaction, String> chipLabels;
}

class SensoryOptionDefinitions {
  SensoryOptionDefinitions.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported sensory option definitions');
    }
    final rawReasons = json['reasons'] as Map;
    if (rawReasons.length != 2) {
      throw const FormatException('Expected liked and disliked reasons');
    }
    reasons = Map.unmodifiable({
      for (final side in TasteReaction.sides)
        side: _readReasons(rawReasons[side.name] as List),
    });
    final options = <String, MouthfeelDefinition>{};
    for (final raw in json['mouthfeel'] as List) {
      final row = raw as Map;
      final key = _requiredText(row, 'key');
      if (options.containsKey(key)) {
        throw FormatException('Duplicate mouthfeel: $key');
      }
      final chips = row['chip_ko'] as Map? ?? const {};
      options[key] = MouthfeelDefinition(
        key: key,
        label: _requiredText(row, 'label_ko'),
        axis: _requiredText(row, 'axis'),
        axisLabel: _requiredText(row, 'axis_label_ko'),
        chipLabels: Map.unmodifiable({
          for (final side in TasteReaction.values)
            if (chips[side.name] != null) side: _requiredText(chips, side.name),
        }),
      );
    }
    if (options.isEmpty) throw const FormatException('Empty mouthfeel choices');
    mouthfeel = Map.unmodifiable(options);
  }

  late final Map<TasteReaction, Map<String, ReasonDefinition>> reasons;
  late final Map<String, MouthfeelDefinition> mouthfeel;

  static Map<String, ReasonDefinition> _readReasons(List rows) {
    final definitions = <String, ReasonDefinition>{};
    for (final raw in rows) {
      final row = raw as Map;
      final key = _requiredText(row, 'key');
      if (definitions.containsKey(key)) {
        throw FormatException('Duplicate reason: $key');
      }
      final overrides = row['taste_meanings'] as Map? ?? const {};
      definitions[key] = ReasonDefinition(
        key: key,
        label: _requiredText(row, 'label_ko'),
        meaning: _readMeaning(row['meaning']),
        selectable: row['selectable'] as bool? ?? true,
        tasteMeanings: Map.unmodifiable({
          for (final entry in overrides.entries)
            entry.key as String: _readMeaning(entry.value),
        }),
      );
    }
    if (definitions.length != 4) {
      throw const FormatException('Expected four reasons per reaction');
    }
    return Map.unmodifiable(definitions);
  }

  static AnswerMeaning _readMeaning(Object? value) {
    for (final meaning in AnswerMeaning.values) {
      if (meaning.name == value) return meaning;
    }
    throw FormatException('Unknown answer meaning: $value');
  }

  static String _requiredText(Map row, String field) {
    final value = row[field];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Missing sensory option $field');
    }
    return value;
  }
}
