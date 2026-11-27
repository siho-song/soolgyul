import 'dart:collection';

import 'revisit_intent.dart';
import 'sensory_gauges.dart';

/// Where an aroma was noticed: on the nose (Step 1), in the mouth (Step 2)
/// or after swallowing (Step 3). Each is picked and stored apart.
enum AromaStage { nose, palate, finish }

/// The pages of the questionnaire. The whole flow asks the palate's gauges
/// and the finish's on one page, [palate]; [finish] is the page of the
/// finish asked again on its own.
enum SensoryPage { revisit, nose, palate, finish, review, complete }

/// A part of the questionnaire asked again on its own, of a record already
/// answered: 향, 맛과 질감 (its gauges and the flavours in the mouth),
/// 마무리와 여운 (its gauges and the aromas left).
enum SensoryPart {
  aroma,
  palate,
  finish;

  SensoryPage get _page => switch (this) {
    aroma => SensoryPage.nose,
    palate => SensoryPage.palate,
    finish => SensoryPage.finish,
  };
}

/// The headings the review page lists the answers under.
enum SensoryReviewSection {
  nose,
  palate,
  flavor,
  finish;

  bool _belongsTo(SensoryPart part) => switch (this) {
    nose => part == SensoryPart.aroma,
    palate || flavor => part == SensoryPart.palate,
    finish => part == SensoryPart.finish,
  };
}

/// One answer the review page lists: an aroma of a stage, or the step chosen
/// on a gauge.
class SensoryAnswerItem {
  const SensoryAnswerItem.aroma(AromaStage this.stage, this.key);
  const SensoryAnswerItem.level(this.key) : stage = null;

  /// Null for a gauge.
  final AromaStage? stage;

  /// The aroma's dictionary key, or the gauge's axis.
  final String key;

  /// Names the item among a flow's answers.
  String get id => switch (stage) {
    final stage? => 'aroma:${stage.name}:$key',
    null => 'level:$key',
  };
}

/// Shared in-memory navigation contract. No DB writes or card interpretation.
///
/// After 재음용 의사 the pages run nose, then palate with the finish under
/// it: aromas picked on the nose, and a step from 1 to 5 on each gauge the
/// drink is asked. Any one
/// page may be left empty, but not all of them: a record says at least one
/// thing that was sensed. The flow ends on the review page, where an answer
/// may be marked as a burden; everything not marked is stored as liked.
class SensoryQuestionFlow {
  SensoryQuestionFlow({
    required Set<String> aromaKeys,
    required this.gauges,
    this.only,
  }) : aromaKeys = Set.unmodifiable(aromaKeys);

  final Set<String> aromaKeys;

  /// The gauges this drink's kind is asked.
  final GaugeSet gauges;

  /// The one part whose page the flow walks; null walks them all.
  final SensoryPart? only;

  RevisitIntent? _revisit;
  RevisitIntent? get revisit => _revisit;

  final _aromas = {for (final stage in AromaStage.values) stage: <String>{}};
  final _levels = <String, int>{};
  final _burdens = <String>{};
  bool _noseSkipped = false;

  late SensoryPage _current = pages.first;
  SensoryPage get current => _current;

  /// The aromas picked at [stage], in the order they were picked. The set is
  /// a live view: it shows later picks too.
  Set<String> aromas(AromaStage stage) => UnmodifiableSetView(_aromas[stage]!);

  /// Whether the nose question was passed with SKIP, nothing picked.
  bool get noseSkipped => _noseSkipped;

  /// The step chosen on the gauge of [axis], 1 to 5; null while none is.
  int? level(String axis) => _levels[axis];

  void setRevisit(RevisitIntent value) {
    _revisit = value;
  }

  /// Picks an aroma at [stage], or unpicks one already picked there, which
  /// also takes its burden mark away.
  void toggleAroma(AromaStage stage, String key) {
    if (!aromaKeys.contains(key)) throw ArgumentError.value(key, 'aroma');
    if (stage == AromaStage.nose) _noseSkipped = false;
    final picked = _aromas[stage]!;
    if (picked.remove(key)) {
      _burdens.remove(SensoryAnswerItem.aroma(stage, key).id);
    } else {
      picked.add(key);
    }
  }

  /// Leaves the nose question as skipped, with nothing picked.
  void skipNose() {
    for (final key in _aromas[AromaStage.nose]!) {
      _burdens.remove(SensoryAnswerItem.aroma(AromaStage.nose, key).id);
    }
    _aromas[AromaStage.nose]!.clear();
    _noseSkipped = true;
  }

  /// Chooses [level] on the gauge of [axis]; choosing the step already
  /// chosen keeps it. A different step takes the axis's burden mark away:
  /// the mark was about the step that has just changed.
  void chooseLevel(String axis, int level) {
    if (gauges.of(axis) == null) throw ArgumentError.value(axis, 'axis');
    if (level < 1 || level > SensoryGauge.steps) {
      throw ArgumentError.value(level, 'level');
    }
    if (_levels[axis] == level) return;
    _burdens.remove(SensoryAnswerItem.level(axis).id);
    _levels[axis] = level;
  }

  /// The step every gauge of a new record starts on. A gauge left where it
  /// starts is answered with it: the middle is what was felt.
  static const startingLevel = 3;

  /// Sets every gauge this drink is asked on [startingLevel], as a new
  /// record begins.
  void startGaugesInTheMiddle() {
    for (final gauge in gauges.palate.followedBy(gauges.finish)) {
      _levels[gauge.axis] = startingLevel;
    }
  }

  bool _answered(SensoryAnswerItem item) => switch (item.stage) {
    final stage? => _aromas[stage]!.contains(item.key),
    null => _levels.containsKey(item.key),
  };

  /// Whether [item] is marked as a burden; one not marked is liked.
  bool isBurden(SensoryAnswerItem item) => _burdens.contains(item.id);

  /// Marks an answer as a burden, or takes the mark away.
  void toggleBurden(SensoryAnswerItem item) {
    if (!_answered(item)) throw ArgumentError.value(item.id, 'item');
    if (!_burdens.remove(item.id)) _burdens.add(item.id);
  }

  /// The headings of the review page, those of [only]'s part when the flow
  /// walks one part.
  List<SensoryReviewSection> get reviewSections {
    final part = only;
    return [
      for (final section in SensoryReviewSection.values)
        if (part == null || section._belongsTo(part)) section,
    ];
  }

  /// The answers the review page lists under [section], as their pages show
  /// them: gauges in the kind's order, aromas in the order picked.
  List<SensoryAnswerItem> reviewItems(SensoryReviewSection section) {
    List<SensoryAnswerItem> levels(List<SensoryGauge> asked) => [
      for (final gauge in asked)
        if (_levels.containsKey(gauge.axis))
          SensoryAnswerItem.level(gauge.axis),
    ];
    List<SensoryAnswerItem> picked(AromaStage stage) => [
      for (final key in _aromas[stage]!) SensoryAnswerItem.aroma(stage, key),
    ];
    return switch (section) {
      SensoryReviewSection.nose => picked(AromaStage.nose),
      SensoryReviewSection.palate => levels(gauges.palate),
      SensoryReviewSection.flavor => picked(AromaStage.palate),
      SensoryReviewSection.finish => [
        ...levels(gauges.finish),
        ...picked(AromaStage.finish),
      ],
    };
  }

  /// The review page is asked only with something to review.
  bool get _asksReview =>
      reviewSections.any((section) => reviewItems(section).isNotEmpty);

  List<SensoryPage> get pages => List.unmodifiable([
    ...switch (only) {
      final part? => [part._page],
      null => const [SensoryPage.revisit, SensoryPage.nose, SensoryPage.palate],
    },
    if (_asksReview) SensoryPage.review,
    SensoryPage.complete,
  ]);

  /// Whether the page shown is the first one the flow asks.
  bool get onFirstQuestion => pages.first == _current;

  /// Whether the page shown is the last one the flow asks.
  bool get onLastQuestion {
    final path = pages;
    return path.indexOf(_current) == path.length - 2;
  }

  /// Whether anything sensed is answered: an aroma at any stage, or a step
  /// on any gauge. The revisit answer and a skipped nose are not.
  bool get hasSensation =>
      _levels.isNotEmpty || _aromas.values.any((picked) => picked.isNotEmpty);

  /// Whether the page shown is the last that takes sensations and the record
  /// still holds none. The page is not left so: the revisit answer alone
  /// makes no record.
  bool get waitsForSensation =>
      _current == (only?._page ?? SensoryPage.palate) && !hasSensation;

  /// Whether the page shown asks the finish's gauges under the palate's:
  /// the palate page of the whole flow.
  bool get asksFinishWithPalate =>
      only == null && _current == SensoryPage.palate;

  bool get canContinue => switch (_current) {
    _ when waitsForSensation => false,
    SensoryPage.revisit => _revisit != null,
    // The nose question waits for a pick; SKIP is the way past it, and a
    // page already skipped may be left again. Asked again on its own there
    // is no SKIP, so the page may be left empty.
    SensoryPage.nose =>
      only != null || _noseSkipped || _aromas[AromaStage.nose]!.isNotEmpty,
    SensoryPage.complete => false,
    // The gauges, the other aromas and the review may all be left as they are.
    _ => true,
  };

  void next() {
    if (!canContinue) throw StateError('the current question is not answered');
    final path = pages;
    _current = path[path.indexOf(_current) + 1];
  }

  void back() {
    final path = pages;
    final index = path.indexOf(_current);
    if (index > 0) _current = path[index - 1];
  }
}
