import 'revisit_intent.dart';
import 'finish_choices.dart';
import 'sensory_asked_keys.dart';
import 'sensory_question_flow.dart';
import 'sensory_option_definitions.dart';
import 'taste_reactions.dart';

export 'sensory_option_definitions.dart' show AnswerMeaning, AnswerPhase;

/// An explicit answer fact, not a cross-answer insight or permanent preference.
class SensoryMeaning {
  const SensoryMeaning({
    required this.id,
    required this.label,
    required this.phase,
    required this.meaning,
    this.section,
    this.subject,
    this.reaction,
    String? shortLabel,
  }) : shortLabel = shortLabel ?? label;
  final String id;
  final String label;

  /// What a chip calls this answer; the full [label] when none is shorter.
  final String shortLabel;
  final AnswerPhase phase;
  final AnswerMeaning meaning;
  final SensorySection? section;
  final String? subject;
  final TasteReaction? reaction;
}

/// Meaning keys are independent of sentence templates and product evidence.
/// Product tags, source aliases and free text must never become user answers.
class SensoryMeaningRegistry {
  SensoryMeaningRegistry({
    required Map<String, dynamic> vocabulary,
    required Map<String, dynamic> tasteBank,
    required this.definitions,
  }) {
    _registerAromas(vocabulary);
    _registerTastes(tasteBank);
    _registerMouthfeel();
    _registerRevisit();
    _registerFinish();
    _registerUnansweredStates();
  }

  void _registerAromas(Map<String, dynamic> vocabulary) {
    for (final raw in vocabulary['groups'] as List) {
      final group = raw as Map;
      if (group['domain'] != 'descriptor' ||
          !(group['phases'] as List).contains('aroma')) {
        continue;
      }
      final key = group['key'] as String;
      if (!_aromas.add(key)) throw FormatException('Duplicate aroma: $key');
      _addSensation(
        SensorySection.aroma,
        key,
        group['label_ko'] as String,
        true,
      );
      // Aromas are no longer asked a target or reasons (2026-11-04). The
      // published options stay defined so stored answers remain readable.
      for (final side in TasteReaction.sides) {
        for (final reason in definitions.reasons[side]!.values) {
          _addReason(SensorySection.aroma, key, side, reason.key, reason.label);
        }
      }
    }
    if (_aromas.isEmpty) throw const FormatException('Empty aroma dictionary');
  }

  void _registerTastes(Map<String, dynamic> tasteBank) {
    final seenTastes = <String>{};
    for (final raw in tasteBank['entries'] as List) {
      final entry = raw as Map;
      final key = entry['key'] as String;
      if (!SensoryQuestionFlow.tasteKeys.contains(key) ||
          !seenTastes.add(key) ||
          entry['kind'] != 'basic_taste') {
        throw FormatException('Invalid taste: $key');
      }
      _addSensation(
        SensorySection.taste,
        key,
        entry['label_ko'] as String,
        false,
      );
      for (final side in TasteReaction.sides) {
        final reasons =
            entry[side == TasteReaction.liked
                    ? 'positive_reasons'
                    : 'negative_reasons']
                as List;
        final seen = <String>{};
        for (final rawReason in reasons) {
          final reason = rawReason as Map;
          final reasonKey = reason['key'] as String;
          if (!seen.add(reasonKey)) {
            throw FormatException('Duplicate reason: $key/$reasonKey');
          }
          _addReason(
            SensorySection.taste,
            key,
            side,
            reasonKey,
            reason['label_ko'] as String,
            reason['chip_ko'] as String,
          );
        }
        if (seen.length != 4) throw FormatException('Incomplete reasons: $key');
      }
    }
    if (seenTastes.length != SensoryQuestionFlow.tasteKeys.length) {
      throw const FormatException('Incomplete tastes');
    }
  }

  void _registerMouthfeel() {
    if (definitions.mouthfeel.keys
            .toSet()
            .difference(SensoryQuestionFlow.mouthfeelKeys)
            .isNotEmpty ||
        definitions.mouthfeel.length !=
            SensoryQuestionFlow.mouthfeelKeys.length) {
      throw const FormatException('Invalid mouthfeel choices');
    }
    for (final option in definitions.mouthfeel.values) {
      _addSensation(
        SensorySection.mouthfeel,
        option.key,
        option.label,
        true,
        shortLabels: option.chipLabels,
      );
    }
  }

  void _registerRevisit() {
    for (final intent in RevisitIntent.values) {
      _add(
        SensoryMeaning(
          id: 'revisit:${intent.name}',
          label: intent.name,
          phase: AnswerPhase.overall,
          meaning: switch (intent) {
            RevisitIntent.wantAgain => AnswerMeaning.revisitDesired,
            RevisitIntent.wouldAcceptAgain => AnswerMeaning.revisitAcceptable,
            RevisitIntent.doNotWantAgain => AnswerMeaning.revisitDeclined,
            RevisitIntent.unsure => AnswerMeaning.unknown,
          },
        ),
      );
    }
  }

  void _registerFinish() {
    for (final option in FinishOption.values) {
      _add(
        SensoryMeaning(
          id: 'finish:${option.name}',
          label: option.chip,
          phase: AnswerPhase.afterSwallowing,
          subject: option.family,
          reaction: option.positive
              ? TasteReaction.liked
              : TasteReaction.disliked,
          meaning: switch (option) {
            FinishOption.pleasantLength => AnswerMeaning.pleasantPersistence,
            FinishOption.clean => AnswerMeaning.quickClearing,
            FinishOption.tooShort => AnswerMeaning.tooBrief,
            FinishOption.heavy => AnswerMeaning.heavyResidue,
            FinishOption.aromaEcho => AnswerMeaning.lingeringAroma,
            FinishOption.offFlavor => AnswerMeaning.lingeringOffFlavor,
          },
        ),
      );
    }
  }

  void _registerUnansweredStates() {
    // Tastes are always answered; the other sections may stay 잘 모르겠어요.
    for (final section in ['aroma', 'mouthfeel', 'finish']) {
      for (final entry in {'unsure': AnswerMeaning.unknown}.entries) {
        _add(
          SensoryMeaning(
            id: '$section:${entry.key}',
            label: entry.key,
            phase: section == 'finish'
                ? AnswerPhase.afterSwallowing
                : AnswerPhase.duringDrinking,
            meaning: entry.value,
            subject: section,
          ),
        );
      }
    }
  }

  /// Must equal SENSORY_MEANING_VERSION on the server; a Deno contract test
  /// reads this file to check it.
  static const version = 'sensory-answer-meaning-v1';
  final _entries = <String, SensoryMeaning>{};
  final _aromas = <String>{};
  Set<String> get aromaKeys => Set.unmodifiable(_aromas);
  Map<String, SensoryMeaning> get entries => Map.unmodifiable(_entries);
  SensoryMeaning lookup(String id) =>
      _entries[id] ?? (throw ArgumentError.value(id, 'answerId'));

  /// The name of the answer [id]; null for one the registry does not define.
  String? labelOf(String id) => _entries[id]?.label;

  final SensoryOptionDefinitions definitions;

  void _add(SensoryMeaning meaning) {
    if (meaning.label.trim().isEmpty ||
        meaning.shortLabel.trim().isEmpty ||
        _entries.containsKey(meaning.id)) {
      throw FormatException('Invalid meaning: ${meaning.id}');
    }
    _entries[meaning.id] = meaning;
  }

  void _addSensation(
    SensorySection section,
    String key,
    String label,
    bool notice, {
    Map<TasteReaction, String> shortLabels = const {},
  }) {
    if (notice) {
      _add(
        SensoryMeaning(
          id: 'notice:${section.name}:$key',
          label: label,
          section: section,
          subject: key,
          phase: AnswerPhase.duringDrinking,
          meaning: AnswerMeaning.noticed,
        ),
      );
    }
    for (final side in TasteReaction.sides) {
      _add(
        SensoryMeaning(
          id: 'reaction:${section.name}:$key:${side.name}',
          label: label,
          section: section,
          subject: key,
          phase: AnswerPhase.duringDrinking,
          meaning: AnswerMeaning.evaluated,
          reaction: side,
          shortLabel: shortLabels[side],
        ),
      );
      // No section asks a target any more (aromas 2026-11-04, tastes
      // 2026-11-05). The published options stay defined so stored answers
      // remain readable.
      if (section != SensorySection.mouthfeel) {
        _add(
          SensoryMeaning(
            id: 'target:${section.name}:$key:${side.name}',
            label: label,
            section: section,
            subject: key,
            phase: AnswerPhase.duringDrinking,
            meaning: AnswerMeaning.reasonTargetSelected,
            reaction: side,
          ),
        );
      }
    }
  }

  void _addReason(
    SensorySection section,
    String key,
    TasteReaction side,
    String reason,
    String label, [
    String? shortLabel,
  ]) {
    final definition = definitions.reasons[side]?[reason];
    if (definition == null) throw FormatException('Unknown reason: $reason');
    final meaning = section == SensorySection.taste
        ? definition.meaningForTaste(key)
        : definition.meaning;
    _add(
      SensoryMeaning(
        id: 'reason:${section.name}:$key:${side.name}:$reason',
        label: label,
        section: section,
        subject: key,
        phase: AnswerPhase.duringDrinking,
        meaning: meaning,
        reaction: side,
        shortLabel: shortLabel,
      ),
    );
  }

  /// Current choices only; [lookup] also accepts retired answer definitions.
  Set<String> reasonKeys(
    SensorySection section,
    String key,
    TasteReaction side,
  ) {
    final prefix = 'reason:${section.name}:$key:${side.name}:';
    return Set.unmodifiable(
      _entries.keys
          .where((id) => id.startsWith(prefix))
          .map((id) => id.substring(prefix.length))
          .where((reason) => definitions.reasons[side]![reason]!.selectable),
    );
  }

  /// A flow of every question, or with [only] of that part's alone.
  SensoryQuestionFlow createFlow([
    SensoryAskedKeys asked = SensoryAskedKeys.all,
    SensoryPart? only,
  ]) => SensoryQuestionFlow(
    aromaKeys: aromaKeys,
    reasonKeys: reasonKeys,
    askedTasteKeys: asked.tasteKeys,
    askedMouthfeelKeys: asked.mouthfeelKeys,
    only: only,
  );

  /// The inverse of [readAnswers]: marks in [flow] the answers stored under
  /// [ids]. An answer the questionnaire no longer offers, or does not ask
  /// of the flow's kind of drink, is left out.
  void restoreAnswers(SensoryQuestionFlow flow, Iterable<String> ids) {
    final stored = ids.toSet();
    final answers = <SensoryMeaning>[for (final id in stored) ?_entries[id]];
    Iterable<SensoryMeaning> of(String kind) =>
        answers.where((answer) => answer.id.startsWith('$kind:'));

    for (final answer in of('revisit')) {
      flow.setRevisit(RevisitIntent.values.byName(answer.id.split(':').last));
    }
    for (final section in [SensorySection.aroma, SensorySection.mouthfeel]) {
      if (stored.contains('${section.name}:unsure')) flow.setUnsure(section);
    }
    for (final answer in of('notice')) {
      final section = answer.section!;
      final key = answer.subject!;
      final selected = flow.selected(section);
      final asked = section == SensorySection.aroma
          ? flow.aromaKeys.contains(key) && selected.length < 5
          : flow.askedMouthfeelKeys.contains(key);
      if (asked && !selected.contains(key)) flow.toggleNotice(section, key);
    }
    for (final answer in of('reaction')) {
      final section = answer.section!;
      final key = answer.subject!;
      final side = answer.reaction!;
      final asked = section == SensorySection.taste
          ? flow.askedTasteKeys.contains(key)
          : flow.selected(section).contains(key);
      if (asked && flow.reactions(section)[key] != side) {
        flow.toggleReaction(section, key, side);
      }
    }
    // A thing was liked or it was not: one an older answer only named, with
    // nothing said of it, opens as liked.
    for (final section in [SensorySection.aroma, SensorySection.mouthfeel]) {
      for (final key in flow.selected(section).toList()) {
        if (!flow.reactions(section).containsKey(key)) {
          flow.toggleReaction(section, key, TasteReaction.liked);
        }
      }
    }
    // Tastes alone still take reasons, one at most.
    for (final answer in of('reason')) {
      const section = SensorySection.taste;
      final key = answer.subject!;
      final side = answer.reaction!;
      final reason = answer.id.split(':').last;
      if (answer.section == section &&
          flow.reactions(section)[key] == side &&
          reasonKeys(section, key, side).contains(reason) &&
          !flow.reasons(section, key).contains(reason)) {
        flow.toggleReason(section, key, reason);
      }
    }
    if (stored.contains('finish:unsure')) {
      if (!flow.finish.unsure) flow.finish.toggleUnsure();
    }
    for (final answer in of('finish')) {
      final option = FinishOption.values.asNameMap()[answer.id.split(':').last];
      if (option != null && !flow.finish.selected.contains(option)) {
        flow.finish.toggle(option);
      }
    }
  }

  /// Recomputed from current answers: removed or changed answers cannot linger.
  /// No missing selections are filled with neutral/dislike/absence facts.
  List<SensoryMeaning> readAnswers(SensoryQuestionFlow flow) {
    final ids = <String>{};
    if (flow.revisit != null) ids.add('revisit:${flow.revisit!.name}');
    for (final section in SensorySection.values) {
      if (flow.unsure(section)) ids.add('${section.name}:unsure');
      for (final key in flow.selected(section)) {
        ids.add('notice:${section.name}:$key');
      }
      for (final entry in flow.reactions(section).entries) {
        ids.add('reaction:${section.name}:${entry.key}:${entry.value.name}');
        for (final reason in flow.reasons(section, entry.key)) {
          ids.add(
            'reason:${section.name}:${entry.key}:${entry.value.name}:$reason',
          );
        }
      }
    }
    if (flow.finish.unsure) ids.add('finish:unsure');
    for (final option in flow.finish.selected) {
      ids.add('finish:${option.name}');
    }
    final ordered = ids.toList()..sort();
    return List.unmodifiable(ordered.map(lookup));
  }
}
