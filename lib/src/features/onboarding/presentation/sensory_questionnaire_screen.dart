import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_top_bar.dart';
import '../../../widgets/app_chip.dart';
import '../../../widgets/kept_text.dart';
import '../../taste_card/data/taste_card_note_view_data.dart';

import '../adaptive/onboarding_aroma_menu.dart';
import '../../../core/sensory/sensory_gauges.dart';
import '../../../core/sensory/sensory_meanings.dart';
import '../../../core/sensory/sensory_question_flow.dart';
import '../../../core/sensory/revisit_intent.dart';
import 'widgets/onboarding_choice_controls.dart';
import 'widgets/onboarding_layout.dart';
import 'sensory/aroma_picker.dart';
import 'sensory/sensory_gauge.dart';
import 'sensory/sensory_question_copy.dart';
import 'sensory/sensory_review.dart';

/// What a record after the first asks beside 재음용 의사: the colour and the
/// texture its 테이스팅 노트 keeps, which are saved there once the record
/// exists. [chosen] holds the option kept under each field.
class SensoryRecordLook {
  const SensoryRecordLook({
    required this.choices,
    required this.chosen,
    required this.onChoose,
    required this.picker,
  });

  /// Empty for a kind of drink that notes neither.
  final List<TasteCardNoteChoiceViewData> choices;
  final Map<String, String> chosen;

  /// Called with the field and the option kept, or null when it is cleared.
  final void Function(String field, String? option) onChoose;

  /// Draws one choice as the 테이스팅 노트 does: its colours as dabs, its
  /// textures as small glasses, the kept one marked.
  final Widget Function(
    TasteCardNoteChoiceViewData choice,
    String? chosen,
    ValueChanged<String?> onChoose,
  )
  picker;
}

/// The header's SKIP for the current question: [id] is the stored unsure
/// option (`revisit:unsure`, `nose:unsure`) and keys the button.
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

/// The first record and every record after it ask the same pages in the
/// same words: 재음용 의사, the aromas on the nose, the palate (its gauges,
/// then the flavours in the mouth), the finish (its gauges, then the aromas
/// left) and the review page, whose button says 저장.
///
/// A flow of one part alone ([SensoryQuestionFlow.only]) asks a saved
/// record's questions again, in a sheet with no header: the part's page,
/// then the review of that part's answers. It holds the record's other
/// answers too, so the aromas of the parts before lead its picker as they do
/// in the whole flow. A page after the first has 이전
/// under it, a part left with nothing to review ends on 완료, and the nose
/// question left with nothing picked is kept as skipped.
class SensoryQuestionnaireScreen extends StatefulWidget {
  const SensoryQuestionnaireScreen({
    required this.flow,
    required this.registry,
    required this.aromaMenu,
    required this.onChanged,
    required this.onComplete,
    this.skip,
    this.recordLook,
    super.key,
  });

  final SensoryQuestionFlow flow;
  final SensoryMeaningRegistry registry;
  final VoidCallback onChanged;
  final VoidCallback onComplete;

  /// The aroma menu of the drink's category and kind, which the nose
  /// question shows whole; the palate and the finish show its short lists.
  final OnboardingAromaMenu aromaMenu;

  /// Where the screen publishes the header's SKIP for the shown question.
  /// The questions themselves no longer carry a 잘 모르겠어요 button.
  final SensorySkipNotifier? skip;

  /// Given, the first page is a record's: 재음용 의사 asked short, then the
  /// drink's colour and texture. Without it the first record's question
  /// stands as it is.
  final SensoryRecordLook? recordLook;

  @override
  State<SensoryQuestionnaireScreen> createState() =>
      _SensoryQuestionnaireScreenState();
}

class _SensoryQuestionnaireScreenState extends State<SensoryQuestionnaireScreen>
    with SingleTickerProviderStateMixin {
  SensoryQuestionFlow get _flow => widget.flow;
  SensoryPage get _page => _flow.current;

  /// Whether a saved record's questions are asked again.
  bool get _revising => _flow.only != null;

  /// Runs for a moment after the question changes. Until it ends 다음 and
  /// SKIP ignore taps: the second tap of a double tap was meant for the
  /// question that has just left, and would skip this one unread, or send
  /// the record from the last but one. Long enough to outlast a double tap.
  late final AnimationController _settling;

  @override
  void initState() {
    super.initState();
    _settling = AnimationController(vsync: this, duration: AppDurations.slow);
  }

  void _change(VoidCallback update) {
    setState(update);
    widget.onChanged();
  }

  String _aromaLabel(String key) => widget.registry.aromaLabel(key) ?? key;

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

  /// The gauges of a page, each chosen by a tap on one of its five stops or
  /// a drag to it.
  Widget _gauges(List<SensoryGauge> gauges) => SensoryGaugeList(
    gauges: gauges,
    levelOf: _flow.level,
    onChoose: (axis, level) => _change(() => _flow.chooseLevel(axis, level)),
  );

  /// The picker of the aromas noticed at [stage], which holds its own
  /// selection apart from the other stages'.
  Widget _aromas(AromaStage stage) => AromaPicker(
    selected: _flow.aromas(stage),
    onToggle: (key) => _change(() => _flow.toggleAroma(stage, key)),
    keyPrefix: 'aroma:${stage.name}:',
    menu: widget.aromaMenu,
    label: _aromaLabel,
  );

  /// The record's first page: 재음용 의사, 색상 and 질감, each under a
  /// heading of the same size and well apart; the three answers stand on
  /// one line. A kind of drink that notes no colour or texture has 재음용
  /// 의사 alone.
  List<Widget> _recordRevisit(SensoryRecordLook look) {
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Semantics(
        header: true,
        child: KeptText(text, style: AppTextStyles.sectionTitle),
      ),
    );
    return [
      heading(RevisitQuestion.recordTitle),
      Row(
        children: [
          for (final (index, (value, label))
              in RevisitQuestion.recordOptions.indexed) ...[
            if (index > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppChip(
                key: ValueKey('revisit:${value.name}'),
                label: label,
                size: onboardingChoiceChipSize,
                variant: AppChipVariant.outline,
                selected: _flow.revisit == value,
                expand: true,
                onPressed: () => _change(() => _flow.setRevisit(value)),
              ),
            ),
          ],
        ],
      ),
      for (final choice in look.choices) ...[
        const SizedBox(height: _lookSectionGap),
        heading(choice.field == 'appearance' ? '색상' : '질감'),
        KeyedSubtree(
          key: ValueKey('look:${choice.field}'),
          child: look.picker(
            choice,
            look.chosen[choice.field],
            (option) => _change(() => look.onChoose(choice.field, option)),
          ),
        ),
      ],
    ];
  }

  /// The finish under the palate's gauges: its heading and description,
  /// then its gauges.
  List<Widget> _finishSection() {
    const copy = SensoryQuestionCopy(SensoryPage.finish);
    return [
      const SizedBox(height: _lookSectionGap),
      Semantics(
        header: true,
        child: KeptText(copy.title, style: AppTextStyles.sectionTitle),
      ),
      const SizedBox(height: AppSpacing.sm),
      KeptText(copy.description, style: AppTextStyles.onboardingBody),
      const SizedBox(height: AppSpacing.lg),
      KeyedSubtree(
        key: const ValueKey('sensory-finish-section'),
        child: _gauges(_flow.gauges.finish),
      ),
    ];
  }

  /// The room between 재음용 의사, 색상 and 질감, and between the palate's
  /// gauges and the finish's.
  static const _lookSectionGap = 48.0;

  List<Widget> _options() => switch (_page) {
    SensoryPage.revisit when widget.recordLook != null => _recordRevisit(
      widget.recordLook!,
    ),
    SensoryPage.revisit => [
      for (final (value, label) in RevisitQuestion.options)
        _option(
          id: 'revisit:${value.name}',
          label: label,
          selected: _flow.revisit == value,
          onPressed: () => _flow.setRevisit(value),
        ),
    ],
    SensoryPage.nose => [_aromas(AromaStage.nose)],
    SensoryPage.palate => [
      _gauges(_flow.gauges.palate),
      if (_flow.asksFinishWithPalate) ..._finishSection(),
    ],
    SensoryPage.finish => [_gauges(_flow.gauges.finish)],
    SensoryPage.review => [
      SensoryReview(flow: _flow, aromaLabel: _aromaLabel, onChanged: _change),
    ],
    SensoryPage.complete => [],
  };

  /// The header's SKIP for the page shown: 재음용 의사 and the nose alone
  /// are skipped, stored as unsure. The other pages may be left empty with
  /// 다음, so they have none.
  SensorySkip? get _currentSkip => switch (_page) {
    SensoryPage.revisit => (id: 'revisit:unsure', onPressed: _skipAsUnsure),
    SensoryPage.nose => (id: 'nose:unsure', onPressed: _skipAsUnsure),
    _ => null,
  };

  void _skipAsUnsure() {
    if (_settling.isAnimating) return;
    _change(
      () => _page == SensoryPage.revisit
          ? _flow.setRevisit(RevisitIntent.unsure)
          : _flow.skipNose(),
    );
    _advance();
  }

  /// Whether the nose page is shown with nothing picked and not skipped.
  bool get _nosePageIsEmpty =>
      _page == SensoryPage.nose &&
      _flow.aromas(AromaStage.nose).isEmpty &&
      !_flow.noseSkipped;

  void _next() {
    if (_settling.isAnimating) return;
    // Asked again there is no SKIP: the nose left empty is kept as skipped.
    if (_revising && _nosePageIsEmpty) {
      _skipAsUnsure();
    } else {
      _advance();
    }
  }

  void _advance() {
    FocusManager.instance.primaryFocus?.unfocus();
    // Asked again, the sheet closes over its last page as it stands.
    if (_revising && _flow.onLastQuestion) {
      widget.onComplete();
      return;
    }
    if (_page != SensoryPage.complete) {
      _change(_flow.next);
      unawaited(_settling.forward(from: 0));
    }
    if (_page == SensoryPage.complete) widget.onComplete();
  }

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
    _settling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _publishSkip(_currentSkip);
    final copy = SensoryQuestionCopy(_page);
    final recordRevisit =
        _page == SensoryPage.revisit && widget.recordLook != null;
    return OnboardingStepScaffold(
      key: ValueKey('sensory-step:${_page.name}'),
      // Its sections carry their own headings.
      title: recordRevisit ? '' : copy.title,
      titleStyle: AppTextStyles.sectionTitle,
      description: recordRevisit ? '' : copy.description,
      childrenBuilder: (context, layout) => _options(),
      actionNote: _flow.waitsForSensation
          ? SensoryQuestionCopy.sensationRequired
          : null,
      primaryAction: OnboardingStepAction(
        key: const ValueKey('sensory-next'),
        label: switch (_page) {
          SensoryPage.review => '저장',
          _ when _revising && _flow.onLastQuestion => '완료',
          _ => '다음',
        },
        onPressed: _flow.canContinue || _page == SensoryPage.complete
            ? _next
            : null,
      ),
      secondaryAction: _revising && !_flow.onFirstQuestion
          ? OnboardingStepAction(
              key: const ValueKey('sensory-back'),
              label: '이전',
              onPressed: () => _change(_flow.back),
            )
          : null,
    );
  }
}
