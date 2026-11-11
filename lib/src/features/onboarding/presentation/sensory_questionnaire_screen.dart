import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../widgets/app_top_bar.dart';

import '../adaptive/direct_aroma_choices.dart';
import '../adaptive/onboarding_aroma_menu.dart';
import '../../../core/sensory/sensory_meanings.dart';
import '../../../core/sensory/sensory_question_flow.dart';
import '../../../core/sensory/taste_reactions.dart';
import '../../../core/sensory/revisit_intent.dart';
import 'widgets/onboarding_choice_controls.dart';
import 'widgets/onboarding_layout.dart';
import 'sensory/aroma_picker.dart';
import 'sensory/aroma_search_sheet.dart';
import 'sensory/sensory_finish_choices.dart';
import 'sensory/sensory_question_copy.dart';

/// The header's SKIP for the current question: [id] is the stored unsure
/// option (`aroma:unsure`, `finish:unsure`, ...) and keys the button.
typedef SensorySkip = ({String id, VoidCallback onPressed});

/// The channel from the question screen to the header's SKIP. The screen
/// clears it a frame after it leaves, so it remembers being disposed.
class SensorySkipNotifier extends ValueNotifier<SensorySkip?> {
  SensorySkipNotifier() : super(null);

  bool _disposed = false;
  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// SKIP at the header's right end while the shown question may be skipped.
class SensorySkipHeaderAction extends StatelessWidget {
  const SensorySkipHeaderAction({required this.skip, super.key});

  final ValueListenable<SensorySkip?> skip;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SensorySkip?>(
    valueListenable: skip,
    builder: (context, value, _) => value == null
        ? const SizedBox.shrink()
        : AppTopBarTextAction(
            key: ValueKey(value.id),
            label: 'SKIP',
            onPressed: value.onPressed,
          ),
  );
}

const _revisitOptions = <(RevisitIntent, String)>[
  (RevisitIntent.wantAgain, '꼭 다시 마시고 싶어요'),
  (RevisitIntent.wouldAcceptAgain, '기회가 된다면 또 마실래요'),
  (RevisitIntent.doNotWantAgain, '아니요, 다른 술을 마셔볼래요'),
];

/// Both entry paths render the same answers and branching contract.
/// The parent retains the flow when the user opens the optional note screen.
class SensoryQuestionnaireScreen extends StatefulWidget {
  const SensoryQuestionnaireScreen({
    required this.flow,
    required this.registry,
    required this.aromaMenu,
    required this.onChanged,
    required this.onComplete,
    this.aromaEngine,
    this.skip,
    super.key,
  });

  final SensoryQuestionFlow flow;
  final SensoryMeaningRegistry registry;
  final VoidCallback onChanged;
  final VoidCallback onComplete;

  /// The drink category's fixed aroma menu.
  final OnboardingAromaMenu aromaMenu;

  /// The app's record flow searches the aroma dictionary under the
  /// question; the first record has no search.
  final DirectAromaChoiceEngine? aromaEngine;

  /// Where the screen publishes the header's SKIP for the shown question.
  /// The questions themselves no longer carry a 잘 모르겠어요 button.
  final SensorySkipNotifier? skip;

  @override
  State<SensoryQuestionnaireScreen> createState() =>
      _SensoryQuestionnaireScreenState();
}

class _SensoryQuestionnaireScreenState
    extends State<SensoryQuestionnaireScreen> {
  SensoryQuestionFlow get _flow => widget.flow;
  SensoryStep get _step => _flow.current;

  void _change(VoidCallback update) {
    setState(update);
    widget.onChanged();
  }

  String _label(SensorySection section, String key) => widget.registry
      .lookup(
        section == SensorySection.taste
            ? 'reaction:taste:$key:liked'
            : 'notice:${section.name}:$key',
      )
      .label;

  Widget _option({
    required String id,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) => OnboardingLargeOption(
    key: ValueKey(id),
    label: label,
    selected: selected,
    onPressed: () => _change(onPressed),
  );

  static String _reactionLabel(TasteReaction side) => switch (side) {
    TasteReaction.liked => '👍 좋았어요',
    TasteReaction.fine => '👌 적당했어요',
    TasteReaction.disliked => '👎 아쉬웠어요',
  };

  OnboardingChoice _reactionChoice(
    SensorySection section,
    String key,
    TasteReaction side,
  ) => OnboardingChoice(
    id: 'reaction:${section.name}:$key:${side.name}',
    label: _reactionLabel(side),
    selected: _flow.reactions(section)[key] == side,
    onPressed: () => _change(() => _flow.toggleReaction(section, key, side)),
  );

  /// The reason chips under a taste that was liked or a burden. None is
  /// required and one at most is chosen; 적당했어요 has none.
  List<OnboardingChoice> _reasonChoices(String key) {
    const section = SensorySection.taste;
    final side = _flow.reactions(section)[key];
    if (side == null || side == TasteReaction.fine) return const [];
    return [
      for (final reason in widget.registry.reasonKeys(section, key, side))
        OnboardingChoice(
          id: 'reason:taste:$key:$reason',
          label: widget.registry
              .lookup('reason:taste:$key:${side.name}:$reason')
              .shortLabel,
          selected: _flow.reasons(section, key).contains(reason),
          onPressed: () =>
              _change(() => _flow.toggleReason(section, key, reason)),
        ),
    ];
  }

  List<Widget> _tasteOptions() => [
    for (final key in _flow.askedTasteKeys)
      OnboardingReactionPair(
        label: _label(SensorySection.taste, key),
        liked: _reactionChoice(SensorySection.taste, key, TasteReaction.liked),
        fine: _reactionChoice(SensorySection.taste, key, TasteReaction.fine),
        disliked: _reactionChoice(
          SensorySection.taste,
          key,
          TasteReaction.disliked,
        ),
        details: _reasonChoices(key),
      ),
  ];

  /// One row per mouthfeel axis the kind is asked, in the taste page's shape:
  /// 좋았어요 · 적당했어요 · 아쉬웠어요, and on a two-ended axis (무게감, 질감)
  /// the chosen side opens the chips naming which end it was.
  List<Widget> _mouthfeelOptions() {
    const section = SensorySection.mouthfeel;
    final definitions = widget.registry.definitions.mouthfeel;
    return [
      for (final axis in SensoryQuestionFlow.mouthfeelAxes)
        if (axis.where(_flow.askedMouthfeelKeys.contains).toList()
            case final keys when keys.isNotEmpty)
          OnboardingReactionPair(
            label: definitions[keys.first]!.axisLabel,
            liked: _mouthfeelJudgement(keys, TasteReaction.liked),
            fine: _mouthfeelJudgement(keys, TasteReaction.fine),
            disliked: _mouthfeelJudgement(keys, TasteReaction.disliked),
            details: switch (_flow.mouthfeelJudgement(keys)) {
              final side? when keys.length == 2 && side != TasteReaction.fine =>
                [
                  for (final key in keys)
                    OnboardingChoice(
                      id: 'reaction:mouthfeel:$key:${side.name}',
                      label: widget.registry
                          .lookup('reaction:mouthfeel:$key:${side.name}')
                          .shortLabel,
                      selected: _flow.reactions(section)[key] == side,
                      onPressed: () =>
                          _change(() => _flow.chooseMouthfeel(key, side)),
                    ),
                ],
              _ => const [],
            },
          ),
    ];
  }

  OnboardingChoice _mouthfeelJudgement(List<String> axis, TasteReaction side) =>
      OnboardingChoice(
        id: axis.length == 1 || side == TasteReaction.fine
            ? 'reaction:mouthfeel:${axis.last}:${side.name}'
            : 'judge:mouthfeel:${axis.first}:${side.name}',
        label: _reactionLabel(side),
        selected: _flow.mouthfeelJudgement(axis) == side,
        onPressed: () => _change(() => _flow.judgeMouthfeel(axis, side)),
      );

  List<Widget> _options() => switch (_step.page) {
    SensoryPage.revisit => [
      for (final (value, label) in _revisitOptions)
        _option(
          id: 'revisit:${value.name}',
          label: label,
          selected: _flow.revisit == value,
          onPressed: () => _flow.setRevisit(value),
        ),
    ],
    // Only aromas still have a notice page; they take their reaction there.
    SensoryPage.notice => [
      AromaPicker(
        flow: _flow,
        menu: widget.aromaMenu,
        aromaEngine: widget.aromaEngine,
        label: (key) => _label(SensorySection.aroma, key),
        onChanged: _change,
      ),
    ],
    SensoryPage.reaction =>
      _step.section == SensorySection.taste
          ? _tasteOptions()
          : _mouthfeelOptions(),
    SensoryPage.finish => [
      SensoryFinishChoices(flow: _flow, onChanged: _change),
    ],
    SensoryPage.complete => [],
  };

  /// Pages that may be skipped with the header's SKIP, stored as unsure.
  /// Tastes are always answered, so the taste page has no skip.
  bool get _canSkipAsUnsure => switch (_step.page) {
    SensoryPage.revisit || SensoryPage.notice || SensoryPage.finish => true,
    SensoryPage.reaction => _step.section == SensorySection.mouthfeel,
    _ => false,
  };

  String get _unsureId => switch (_step.page) {
    SensoryPage.revisit => 'revisit:unsure',
    SensoryPage.finish => 'finish:unsure',
    _ => '${_step.section!.name}:unsure',
  };

  void _skipAsUnsure() {
    _change(() {
      switch (_step.page) {
        case SensoryPage.revisit:
          _flow.setRevisit(RevisitIntent.unsure);
        case SensoryPage.finish:
          if (!_flow.finish.unsure) _flow.finish.toggleUnsure();
        default:
          _flow.setUnsure(_step.section!);
      }
    });
    _next();
  }

  void _next() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_step.page != SensoryPage.complete) {
      _change(_flow.next);
    }
    if (_step.page == SensoryPage.complete) widget.onComplete();
  }

  SensorySkip? get _currentSkip =>
      _canSkipAsUnsure ? (id: _unsureId, onPressed: _skipAsUnsure) : null;

  /// The header listens to [SensoryQuestionnaireScreen.skip]; it is set
  /// after the frame so the header never rebuilds during this build.
  void _publishSkip(SensorySkip? value) {
    final target = widget.skip;
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (target.isDisposed) return;
      if (value == null && target.value != _lastPublished) return;
      target.value = value;
      _lastPublished = value;
    });
  }

  SensorySkip? _lastPublished;

  @override
  void dispose() {
    _publishSkip(null);
    super.dispose();
  }

  bool get _onAromaPage =>
      _step.page == SensoryPage.notice && _step.section == SensorySection.aroma;

  /// The aroma page waits for a pick; the header's SKIP is the way past it.
  /// A page already skipped (unsure) may be left again with 다음.
  bool get _canContinue =>
      _flow.canContinue &&
      !(_onAromaPage &&
          _flow.selected(SensorySection.aroma).isEmpty &&
          !_flow.unsure(SensorySection.aroma));

  @override
  Widget build(BuildContext context) {
    _publishSkip(_currentSkip);
    final copy = SensoryQuestionCopy(_flow);
    return OnboardingStepScaffold(
      key: ValueKey('sensory-step:${_step.key}'),
      title: copy.title,
      description: copy.description,
      descriptionContent: _onAromaPage ? const AromaTapGuide() : null,
      descriptionTrailing: _onAromaPage
          ? '${_flow.selected(SensorySection.aroma).length}/$maxAromaSelections'
          : null,
      childrenBuilder: (context, layout) => _options(),
      primaryAction: OnboardingStepAction(
        key: const ValueKey('sensory-next'),
        label: '다음',
        onPressed: _canContinue || _step.page == SensoryPage.complete
            ? _next
            : null,
      ),
    );
  }
}
