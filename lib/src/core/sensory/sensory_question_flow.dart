import 'revisit_intent.dart';
import 'finish_choices.dart';
import 'taste_reactions.dart';

enum SensorySection { aroma, taste, mouthfeel }

enum SensoryPage { revisit, notice, reaction, finish, complete }

class SensoryStep {
  const SensoryStep(this.page, [this.section]);
  final SensoryPage page;
  final SensorySection? section;
  String get key => '${page.name}:${section?.name ?? ''}';
}

/// Reason IDs come from the question bank; the flow does not interpret them.
typedef SensoryReasonKeys =
    Set<String> Function(
      SensorySection section,
      String key,
      TasteReaction side,
    );

class _SectionAnswers {
  final selected = <String>{};
  final reactions = <String, TasteReaction>{};

  /// By sensation: the reasons behind a taste that was liked or a burden.
  final reasons = <String, Set<String>>{};
  bool unsure = false;
}

/// Shared in-memory navigation contract. No legacy IDs, DB writes or card
/// interpretation. No section asks a target or a separate reason page: a
/// taste takes its optional reasons on the reaction page, right under the
/// reaction they explain, and the mouthfeel page asks notice and reaction at
/// once, one answer per axis.
class SensoryQuestionFlow {
  SensoryQuestionFlow({
    required Set<String> aromaKeys,
    required this.reasonKeys,
    Set<String> askedTasteKeys = tasteKeys,
    Set<String> askedMouthfeelKeys = mouthfeelKeys,
  }) : aromaKeys = Set.unmodifiable(aromaKeys),
       askedTasteKeys = _subset(tasteKeys, askedTasteKeys),
       askedMouthfeelKeys = _subset(mouthfeelKeys, askedMouthfeelKeys);

  final Set<String> aromaKeys;
  final SensoryReasonKeys reasonKeys;

  /// What this product's kind is asked, in the bank's order (see
  /// [SensoryAskedKeys]); the static sets are every answer the bank defines.
  final Set<String> askedTasteKeys;
  final Set<String> askedMouthfeelKeys;

  static Set<String> _subset(Set<String> all, Set<String> asked) {
    if (asked.isEmpty || !all.containsAll(asked)) {
      throw ArgumentError.value(asked, 'asked keys');
    }
    return Set.unmodifiable(all.where(asked.contains));
  }

  static const tasteKeys = {'sweetness', 'acidity', 'bitterness'};
  static const mouthfeelKeys = {
    'light',
    'heavy',
    'smooth',
    'drying',
    'bubbles',
    'warmth',
  };

  /// The mouthfeel rows: an axis is its two ends or a single sensation, and
  /// takes one answer. The page shows the axes a kind is asked, in this order.
  /// 적당했어요 on a two-ended axis is stored on its second end.
  static const mouthfeelAxes = [
    ['light', 'heavy'],
    ['smooth', 'drying'],
    ['bubbles'],
    ['warmth'],
  ];

  /// 좋았어요 or 아쉬웠어요 on a two-ended axis, waiting for its end (which
  /// of 가벼워서 · 묵직해서); keyed by the axis's first end.
  final _pendingMouthfeel = <String, TasteReaction>{};

  /// The axis (see [mouthfeelAxes]) a row's keys belong to; the row holds
  /// the ends the kind is asked, in axis order.
  List<String> _axisOf(List<String> keys) {
    final axis = mouthfeelAxes.firstWhere(
      (axis) => keys.isNotEmpty && axis.contains(keys.first),
      orElse: () => throw ArgumentError.value(keys, 'mouthfeel axis'),
    );
    if (!keys.every(axis.contains) || !askedMouthfeelKeys.containsAll(keys)) {
      throw ArgumentError.value(keys, 'mouthfeel axis');
    }
    return axis;
  }

  /// The reaction a mouthfeel row shows: a stored answer on either end, or
  /// a judgement still waiting for its end.
  TasteReaction? mouthfeelJudgement(List<String> keys) {
    final axis = _axisOf(keys);
    for (final key in axis) {
      final side = _answers[SensorySection.mouthfeel]!.reactions[key];
      if (side != null) return side;
    }
    return _pendingMouthfeel[axis.first];
  }

  /// One of 좋았어요 · 적당했어요 · 아쉬웠어요 for a mouthfeel row. A single
  /// sensation, and 적당했어요, are stored at once; 좋았어요 or 아쉬웠어요 on a
  /// two-ended row waits for [chooseMouthfeel] to name the end. The same
  /// judgement again clears the row.
  void judgeMouthfeel(List<String> keys, TasteReaction side) {
    final axis = _axisOf(keys);
    final current = mouthfeelJudgement(keys);
    _clearMouthfeelAxis(axis);
    if (current == side) return;
    if (keys.length == 1 || side == TasteReaction.fine) {
      chooseMouthfeel(keys.last, side);
    } else {
      _pendingMouthfeel[axis.first] = side;
    }
  }

  void _clearMouthfeelAxis(List<String> axis) {
    final answer = _answers[SensorySection.mouthfeel]!;
    _pendingMouthfeel.remove(axis.first);
    for (final key in axis) {
      if (answer.selected.contains(key)) {
        toggleNotice(SensorySection.mouthfeel, key);
      }
    }
  }

  final _answers = {
    for (final section in SensorySection.values) section: _SectionAnswers(),
  };
  final finish = FinishSelection();
  RevisitIntent? _revisit;
  RevisitIntent? get revisit => _revisit;
  SensoryStep _current = const SensoryStep(SensoryPage.revisit);
  SensoryStep get current => _current;

  Set<String> selected(SensorySection section) =>
      Set.unmodifiable(_answers[section]!.selected);
  Map<String, TasteReaction> reactions(SensorySection section) =>
      Map.unmodifiable(_answers[section]!.reactions);
  bool unsure(SensorySection section) => _answers[section]!.unsure;
  Set<String> reasons(SensorySection section, String key) =>
      Set.unmodifiable(_answers[section]!.reasons[key] ?? {});

  Set<String> _allowed(SensorySection section) => switch (section) {
    SensorySection.aroma => aromaKeys,
    SensorySection.taste => askedTasteKeys,
    SensorySection.mouthfeel => askedMouthfeelKeys,
  };

  /// A page that disappeared under the current step hands over to the
  /// section's first page.
  void _settle(SensorySection section) {
    if (!steps.any((step) => step.key == _current.key)) {
      _current = SensoryStep(
        section == SensorySection.aroma
            ? SensoryPage.notice
            : SensoryPage.reaction,
        section,
      );
    }
  }

  void setRevisit(RevisitIntent value) {
    _revisit = value;
  }

  void toggleNotice(SensorySection section, String key) {
    if (section == SensorySection.taste || !_allowed(section).contains(key)) {
      throw ArgumentError.value(key);
    }
    final answer = _answers[section]!;
    if (!answer.selected.contains(key) &&
        section == SensorySection.aroma &&
        answer.selected.length == 5) {
      throw StateError('at most five aromas');
    }
    answer.unsure = false;
    if (!answer.selected.remove(key)) {
      answer.selected.add(key);
    } else {
      answer.reactions.remove(key);
      answer.reasons.remove(key);
    }
    _settle(section);
  }

  /// Tastes are always answered, so only aroma and mouthfeel can be unsure.
  void setUnsure(SensorySection section) {
    if (section == SensorySection.taste) throw ArgumentError.value(section);
    final answer = _answers[section]!;
    answer.selected.clear();
    answer.reactions.clear();
    answer.reasons.clear();
    answer.unsure = true;
    if (section == SensorySection.mouthfeel) _pendingMouthfeel.clear();
    _settle(section);
  }

  /// The aroma page asks notice and reaction at once: one tap marks an
  /// aroma liked, a second a burden, a third clears it.
  void cycleAroma(String key) {
    final answer = _answers[SensorySection.aroma]!;
    if (!answer.selected.contains(key)) {
      toggleNotice(SensorySection.aroma, key);
      toggleReaction(SensorySection.aroma, key, TasteReaction.liked);
    } else if (answer.reactions[key] == TasteReaction.liked) {
      toggleReaction(SensorySection.aroma, key, TasteReaction.disliked);
    } else {
      toggleNotice(SensorySection.aroma, key);
    }
  }

  /// The mouthfeel page asks notice and reaction at once, one answer per axis
  /// (see [mouthfeelAxes]): an answer clears the axis's other end, and the
  /// same answer again clears the axis.
  void chooseMouthfeel(String key, TasteReaction side) {
    const section = SensorySection.mouthfeel;
    final answer = _answers[section]!;
    final axis = _axisOf([key]);
    if (answer.reactions[key] == side) {
      _clearMouthfeelAxis(axis);
      return;
    }
    _clearMouthfeelAxis(axis);
    toggleNotice(section, key);
    toggleReaction(section, key, side);
  }

  void toggleReaction(SensorySection section, String key, TasteReaction side) {
    final answer = _answers[section]!;
    if (!_allowed(section).contains(key) ||
        (section != SensorySection.taste && !answer.selected.contains(key))) {
      throw ArgumentError.value(key);
    }
    // Aromas are liked or a burden; 적당했어요 is asked for tastes and mouthfeel.
    if (side == TasteReaction.fine && section == SensorySection.aroma) {
      throw ArgumentError.value(side, 'side');
    }
    answer.unsure = false;
    if (answer.reactions[key] == side) {
      answer.reactions.remove(key);
    } else {
      answer.reactions[key] = side;
    }
    // Reasons explain one reaction; a changed or cleared one drops them.
    answer.reasons.remove(key);
    _settle(section);
  }

  /// Tastes alone take reasons, on a taste that was liked or a burden. None
  /// is required and at most one is chosen: two reasons could contradict
  /// (너무 달아서, 덜 달아서), so a new one replaces the last.
  void toggleReason(SensorySection section, String key, String reason) {
    final answer = _answers[section]!;
    final side = answer.reactions[key];
    if (section != SensorySection.taste ||
        side == null ||
        side == TasteReaction.fine ||
        !reasonKeys(section, key, side).contains(reason)) {
      throw ArgumentError.value(reason);
    }
    if (answer.reasons[key]?.contains(reason) ?? false) {
      answer.reasons.remove(key);
    } else {
      answer.reasons[key] = {reason};
    }
  }

  List<SensoryStep> get steps {
    final result = <SensoryStep>[const SensoryStep(SensoryPage.revisit)];
    for (final section in SensorySection.values) {
      // Aromas take their reaction on the notice page (see [cycleAroma]);
      // tastes and mouthfeel answer everything on one reaction page.
      result.add(
        SensoryStep(
          section == SensorySection.aroma
              ? SensoryPage.notice
              : SensoryPage.reaction,
          section,
        ),
      );
    }
    return List.unmodifiable([
      ...result,
      const SensoryStep(SensoryPage.finish),
      const SensoryStep(SensoryPage.complete),
    ]);
  }

  bool get canContinue => switch (_current.page) {
    SensoryPage.revisit => _revisit != null,
    // Every taste asked gets an answer (좋았어요 · 적당했어요 · 아쉬웠어요).
    SensoryPage.reaction when _current.section == SensorySection.taste =>
      askedTasteKeys.every(reactions(SensorySection.taste).containsKey),
    // A 좋았어요/아쉬웠어요 still needs its end before the page moves on.
    SensoryPage.reaction when _current.section == SensorySection.mouthfeel =>
      _pendingMouthfeel.isEmpty,
    SensoryPage.complete => false,
    _ => true, // The other observations are optional; empty stays unanswered.
  };

  void next() {
    if (!canContinue) throw StateError('the current question is not answered');
    final path = steps;
    _current = path[path.indexWhere((s) => s.key == _current.key) + 1];
  }

  void back() {
    final path = steps;
    final index = path.indexWhere((s) => s.key == _current.key);
    if (index > 0) _current = path[index - 1];
  }
}
