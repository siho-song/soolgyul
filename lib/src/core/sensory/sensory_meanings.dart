import 'revisit_intent.dart';
import 'sensory_gauges.dart';
import 'sensory_question_flow.dart';

/// The questions of the published questionnaire, by the keys their answers
/// are stored under.
abstract final class SensoryQuestionKeys {
  static const revisit = 'sensory_revisit';
  static const noseAroma = 'sensory_nose_aroma';
  static const palateLevel = 'sensory_palate_level';
  static const palateAroma = 'sensory_palate_aroma';
  static const finishLevel = 'sensory_finish_level';
  static const finishAroma = 'sensory_finish_aroma';

  static const all = [
    revisit,
    noseAroma,
    palateLevel,
    palateAroma,
    finishLevel,
    finishAroma,
  ];

  /// The questions [part] answers when it is asked again on its own.
  static List<String> of(SensoryPart part) => switch (part) {
    SensoryPart.aroma => const [noseAroma],
    SensoryPart.palate => const [palateLevel, palateAroma],
    SensoryPart.finish => const [finishLevel, finishAroma],
  };
}

/// One stored answer option read back: an aroma or a gauge's step, and
/// whether it was marked as a burden.
///
/// The options are `aroma:<stage>:<key>:<liked|disliked>` and
/// `level:<axis>:<1-5>:<liked|disliked>`.
class SensoryAnswerOption {
  const SensoryAnswerOption._(this.item, this.level, this.burden);

  final SensoryAnswerItem item;

  /// The step chosen, 1 to 5; null for an aroma.
  final int? level;
  final bool burden;

  static const _liked = 'liked';
  static const _disliked = 'disliked';

  /// Null for an option of another kind (재음용 의사, a skipped nose) and for
  /// one this app cannot read.
  static SensoryAnswerOption? parse(String id) {
    final parts = id.split(':');
    if (parts.length != 4) return null;
    final burden = switch (parts[3]) {
      _liked => false,
      _disliked => true,
      _ => null,
    };
    if (burden == null) return null;
    switch (parts[0]) {
      case 'aroma':
        final stage = AromaStage.values.asNameMap()[parts[1]];
        return stage == null
            ? null
            : SensoryAnswerOption._(
                SensoryAnswerItem.aroma(stage, parts[2]),
                null,
                burden,
              );
      case 'level':
        final level = int.tryParse(parts[2]);
        return level == null || level < 1 || level > SensoryGauge.steps
            ? null
            : SensoryAnswerOption._(
                SensoryAnswerItem.level(parts[1]),
                level,
                burden,
              );
      default:
        return null;
    }
  }

  static String _write(SensoryAnswerItem item, int? level, bool burden) {
    final reaction = burden ? _disliked : _liked;
    return level == null
        ? '${item.id}:$reaction'
        : '${item.id}:$level:$reaction';
  }
}

/// The aromas a reader may pick, and the reading of a flow's answers into
/// the stored option keys and back. What an answer means is the server's to
/// say: product tags, source aliases and free text never become answers
/// here.
class SensoryMeaningRegistry {
  SensoryMeaningRegistry({required Map<String, dynamic> vocabulary}) {
    for (final raw in vocabulary['groups'] as List) {
      final group = raw as Map;
      if (group['domain'] != 'descriptor' ||
          !(group['phases'] as List).contains('aroma')) {
        continue;
      }
      final key = group['key'] as String;
      final label = group['label_ko'] as String;
      if (label.trim().isEmpty || _aromaLabels.containsKey(key)) {
        throw FormatException('Invalid aroma: $key');
      }
      _aromaLabels[key] = label;
    }
    if (_aromaLabels.isEmpty) {
      throw const FormatException('Empty aroma dictionary');
    }
  }

  static const _noseSkipped = 'nose:unsure';

  final _aromaLabels = <String, String>{};
  Set<String> get aromaKeys => Set.unmodifiable(_aromaLabels.keys);

  /// The dictionary's word for an aroma; null for a key it does not hold.
  String? aromaLabel(String key) => _aromaLabels[key];

  /// A flow of every question for a drink asked [gauges], or with [only] of
  /// that part's alone.
  SensoryQuestionFlow createFlow(GaugeSet gauges, {SensoryPart? only}) =>
      SensoryQuestionFlow(aromaKeys: aromaKeys, gauges: gauges, only: only);

  /// The chosen option keys of every question, by the question's key; a
  /// question left unanswered has none. Recomputed from the flow each time,
  /// so removed or changed answers cannot linger, and nothing left empty is
  /// filled in.
  Map<String, List<String>> readAnswers(SensoryQuestionFlow flow) {
    List<String> aromas(AromaStage stage) => [
      for (final key in flow.aromas(stage))
        if (SensoryAnswerItem.aroma(stage, key) case final item)
          SensoryAnswerOption._write(item, null, flow.isBurden(item)),
    ];
    List<String> levels(List<SensoryGauge> gauges) => [
      for (final gauge in gauges)
        if (flow.level(gauge.axis) case final level?)
          if (SensoryAnswerItem.level(gauge.axis) case final item)
            SensoryAnswerOption._write(item, level, flow.isBurden(item)),
    ];
    return {
      SensoryQuestionKeys.revisit: [
        if (flow.revisit case final revisit?) 'revisit:${revisit.name}',
      ],
      SensoryQuestionKeys.noseAroma: flow.noseSkipped
          ? const [_noseSkipped]
          : aromas(AromaStage.nose),
      SensoryQuestionKeys.palateLevel: levels(flow.gauges.palate),
      SensoryQuestionKeys.palateAroma: aromas(AromaStage.palate),
      SensoryQuestionKeys.finishLevel: levels(flow.gauges.finish),
      SensoryQuestionKeys.finishAroma: aromas(AromaStage.finish),
    };
  }

  /// The inverse of [readAnswers]: marks in [flow] the answers stored under
  /// [ids]. An aroma the dictionary no longer offers, or a gauge the flow's
  /// kind of drink is not asked, is left out.
  void restoreAnswers(SensoryQuestionFlow flow, Iterable<String> ids) {
    final stored = ids.toList();
    if (stored.contains(_noseSkipped)) flow.skipNose();
    for (final id in stored) {
      if (id.startsWith('revisit:')) {
        final intent = RevisitIntent.values.asNameMap()[id.substring(8)];
        if (intent != null) flow.setRevisit(intent);
        continue;
      }
      final option = SensoryAnswerOption.parse(id);
      if (option == null) continue;
      final item = option.item;
      switch ((item.stage, option.level)) {
        case (final stage?, _):
          if (!flow.aromaKeys.contains(item.key)) continue;
          if (!flow.aromas(stage).contains(item.key)) {
            flow.toggleAroma(stage, item.key);
          }
        case (null, final level?):
          if (flow.gauges.of(item.key) == null) continue;
          if (flow.level(item.key) != level) flow.chooseLevel(item.key, level);
        case (null, null):
          continue;
      }
      if (option.burden && !flow.isBurden(item)) flow.toggleBurden(item);
    }
  }
}
