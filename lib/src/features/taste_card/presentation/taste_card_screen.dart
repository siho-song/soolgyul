import 'dart:async';

import '../../../design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/format/abv.dart';
import '../../../core/format/dates.dart';
import '../../../core/sensory/revisit_intent.dart';
import '../../../core/sensory/sensory_question_flow.dart';
import '../../../design/app_typography.dart';
import '../../../navigation/app_router.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_sheet.dart';
import '../../../widgets/app_snack_bar.dart';
import '../../../widgets/app_term_tooltip.dart';
import '../../../widgets/kept_text.dart';
import '../../../widgets/level_gauge.dart';
import '../../../widgets/paper_box.dart';
import '../../../widgets/text_underline.dart';
import '../../glossary/presentation/widgets/save_term_button.dart';
import '../../recording/presentation/widgets/drink_result_photo.dart';
import '../../records/data/tasting_note_gateway.dart';
import '../../records/presentation/widgets/record_memo_editor.dart';
import '../../records/presentation/widgets/record_price_editor.dart';
import '../../records/presentation/widgets/tasting_note_editor.dart';
import 'widgets/taste_card_answers_editor.dart';
import 'widgets/taste_card_guide_body.dart';
import 'widgets/taste_card_guide_parts.dart';
import 'widgets/taste_card_note_opener.dart';
import '../data/taste_card_snapshot_view_data.dart';

part 'card/taste_card_actions.dart';
part 'card/taste_card_bite_section.dart';
part 'card/taste_card_common.dart';
part 'card/taste_card_drink_header.dart';
part 'card/taste_card_note_entries.dart';
part 'card/taste_card_note_glass.dart';
part 'card/taste_card_note_head.dart';
part 'card/taste_card_note_marks.dart';
part 'card/taste_card_note_paint.dart';
part 'card/taste_card_note_palette.dart';
part 'card/taste_card_note_parts.dart';
part 'card/taste_card_note_sheet.dart';
part 'card/taste_card_reason_section.dart';
part 'card/taste_card_tabs.dart';

enum TasteCardLoadState { loading, retryable, failure }

class TasteCardStatusScreen extends StatelessWidget {
  const TasteCardStatusScreen({
    required this.state,
    this.onRetry,
    this.savedCard = false,
    super.key,
  });

  final TasteCardLoadState state;
  final VoidCallback? onRetry;

  /// Whether a saved card is being opened rather than a new one made.
  final bool savedCard;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (state) {
      TasteCardLoadState.loading when savedCard => (
        '술결 카드를 불러오고 있어요',
        '잠시만 기다려 주세요.',
      ),
      _ when savedCard => ('술결 카드를 불러오지 못했어요', '잠시 후 다시 시도해 주세요.'),
      TasteCardLoadState.loading => (
        '나만의 술결을 분석하고 있어요',
        '남겨주신 감각을 바탕으로 다음 잔의 기준을 찾고 있어요.',
      ),
      TasteCardLoadState.retryable => (
        '네트워크 연결이 불안정해요',
        '작성한 내용은 안전하게 보관 중이에요. 다시 시도해 주세요.',
      ),
      TasteCardLoadState.failure => (
        '술결 카드를 완성하지 못했어요',
        '입력한 내용은 저장되어 있어요. 잠시 후 다시 시도해 주세요.',
      ),
    };
    return PopScope<Object?>(
      // While a new card is being made the page cannot be swiped away:
      // the request is already sent, and answers changed behind it would
      // send a second one. A saved card being opened can be left.
      canPop: state != TasteCardLoadState.loading || savedCard,
      child: ColoredBox(
        color: _TasteCardColors.canvas,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (state == TasteCardLoadState.loading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 28),
                      child: CircularProgressIndicator(
                        color: _TasteCardColors.wine,
                      ),
                    ),
                  KeptText(
                    title,
                    textAlign: TextAlign.center,
                    style: _TasteCardText.headline,
                  ),
                  const SizedBox(height: 14),
                  KeptText(
                    body,
                    textAlign: TextAlign.center,
                    style: _TasteCardText.body,
                  ),
                  if (state != TasteCardLoadState.loading) ...<Widget>[
                    const SizedBox(height: 30),
                    AppButton(label: '다시 시도', onPressed: onRetry),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TasteCardScreen extends StatefulWidget {
  const TasteCardScreen({
    required this.viewData,
    this.onSave,
    this.onOpenApp,
    this.recordPrice,
    this.noteEntries,
    this.recordMemo,
    this.answers,
    this.noteOpener,
    super.key,
  });

  /// The 저장 button's action; null leaves the button out, as on a saved
  /// card opened again.
  final VoidCallback? onSave;

  /// The card the server wrote.
  final TasteCardSnapshotViewData viewData;

  /// On the web the card ends the onboarding: instead of the save button a
  /// bar fixed at the bottom sends the visitor to the app.
  final VoidCallback? onOpenApp;

  /// The app record's 구매 정보 under the drink; null shows none.
  final RecordPriceEditor? recordPrice;

  /// What the owner enters on the 테이스팅 노트 of a saved app record; null
  /// leaves the note read only, with no slot to write in.
  final TastingNoteEditor? noteEntries;

  /// The record's one-line memo, which the note shows and takes as its
  /// 한 줄 총평 when [noteEntries] is given.
  final RecordMemoEditor? recordMemo;

  /// The record's answers, which the owner corrects from the 테이스팅 노트
  /// when [noteEntries] is given. The note redraws a corrected part itself;
  /// the card is written again from the corrections when the note is left:
  /// for the 술결 카드 tab, for another screen, or with the app.
  final TasteCardAnswersEditor? answers;

  /// The header's ⋮ menu asks through it for the 총평 or the price: the
  /// screen turns to its 테이스팅 노트 and opens that sheet there.
  final TasteCardNoteOpener? noteOpener;

  @override
  State<TasteCardScreen> createState() => _TasteCardScreenState();
}

class _TasteCardScreenState extends State<TasteCardScreen> {
  // A card with a 테이스팅 노트 opens on its own tab.
  var _tab = _CardTab.card;

  /// The card written again from corrected answers, shown until the parent
  /// hands the screen a card of its own.
  TasteCardSnapshotViewData? _rewritten;

  /// Whether the 술결 카드 tab waits for the card to be written again.
  var _rewriting = false;

  /// Whether leaving the screen waits for it.
  var _leaving = false;

  /// Whether the question of a card that could not be written is up, over
  /// which nothing spins.
  var _askingToRetry = false;

  /// The app's router, whose back asks [_mayLeave] first; null on a screen
  /// shown outside it.
  AppRouter? _router;
  late final AppLifecycleListener _lifecycle;

  TasteCardSnapshotViewData get _viewData => _rewritten ?? widget.viewData;

  bool get _hasCorrections => widget.answers?.hasPending ?? false;

  @override
  void initState() {
    super.initState();
    widget.answers?.addListener(_correctionsChanged);
    widget.noteOpener?.addListener(_noteAsked);
    // The app may not come back: the corrections are sent as it goes.
    _lifecycle = AppLifecycleListener(
      onPause: () => unawaited(_rewriteInBackground()),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _router = AppRouterScope.maybeOf(context);
    _guardLeave();
  }

  @override
  void didUpdateWidget(covariant TasteCardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.answers != widget.answers) {
      oldWidget.answers?.removeListener(_correctionsChanged);
      widget.answers?.addListener(_correctionsChanged);
      _guardLeave();
    }
    if (oldWidget.noteOpener != widget.noteOpener) {
      oldWidget.noteOpener?.removeListener(_noteAsked);
      widget.noteOpener?.addListener(_noteAsked);
    }
    final snapshotRef = widget.viewData.snapshotRef;
    if (oldWidget.viewData.snapshotRef == snapshotRef) return;
    // The parent's card is the one to show; the card this screen had
    // written again keeps the screen as it stands.
    final sameCard = _rewritten?.snapshotRef == snapshotRef;
    _rewritten = null;
    if (!sameCard) _tab = _CardTab.card;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.answers?.removeListener(_correctionsChanged);
    widget.noteOpener?.removeListener(_noteAsked);
    if (_router?.leaveGuard == _mayLeave) _router?.leaveGuard = null;
    // Left some other way than back: the corrections are sent all the same.
    unawaited(widget.answers?.flush());
    super.dispose();
  }

  void _correctionsChanged() {
    if (!mounted) return;
    _guardLeave();
    // The swipe back is off while a correction waits.
    setState(() {});
  }

  /// The header's back and the system back ask [_mayLeave] first while a
  /// correction waits to be sent.
  void _guardLeave() {
    final router = _router;
    if (router == null) return;
    if (_hasCorrections) {
      router.leaveGuard = _mayLeave;
    } else if (router.leaveGuard == _mayLeave) {
      router.leaveGuard = null;
    }
  }

  /// Has the card written again from the corrected answers and shows the
  /// card that comes back; null with nothing corrected.
  Future<TasteCardRewrite?> _rewrite() async {
    final answers = widget.answers;
    if (answers == null || !answers.hasPending) return null;
    final rewrite = await answers.flush();
    if (mounted && rewrite.card != null) {
      setState(() => _rewritten = rewrite.card!.viewData);
    }
    return rewrite;
  }

  /// The ⋮ menu chose 총평 or 구매 정보: the 테이스팅 노트 comes up and the
  /// sheet opens over it once it shows. A card with no note opens the
  /// sheet where it is.
  void _noteAsked() {
    final slot = widget.noteOpener?.take();
    if (slot == null || !mounted) return;
    if (_viewData.note == null || _tab == _CardTab.note) {
      _openNoteSheet(slot);
      return;
    }
    _selectTab(_CardTab.note);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openNoteSheet(slot));
  }

  void _openNoteSheet(TasteCardNoteSlot slot) {
    if (!mounted) return;
    switch (slot) {
      case TasteCardNoteSlot.overall:
        unawaited(widget.recordMemo?.edit(context, title: '총평'));
      case TasteCardNoteSlot.price:
        unawaited(widget.recordPrice?.edit(context));
    }
  }

  void _selectTab(_CardTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (tab == _CardTab.card) unawaited(_rewriteForCardTab());
  }

  /// The note is left for the card: with answers corrected, the card tab
  /// waits for the card they make. One that could not be written leaves
  /// the old card and the corrections as they are, and says so.
  Future<void> _rewriteForCardTab() async {
    if (!_hasCorrections) return;
    setState(() => _rewriting = true);
    final rewrite = await _rewrite();
    if (!mounted) return;
    setState(() => _rewriting = false);
    switch (rewrite?.status) {
      case TasteCardRewriteStatus.failed:
        showAppSnackBar(context, TasteCardAnswersEditor.rewriteFailure);
      case TasteCardRewriteStatus.conflicted:
        showAppSnackBar(context, TasteCardAnswersEditor.conflictNotice);
      default:
    }
  }

  /// The app goes to the background: the corrections are sent with nothing
  /// shown. A failure leaves them waiting.
  Future<void> _rewriteInBackground() async {
    final rewrite = await _rewrite();
    if (mounted && rewrite?.status == TasteCardRewriteStatus.conflicted) {
      showAppSnackBar(context, TasteCardAnswersEditor.conflictNotice);
    }
  }

  /// Whether the screen may be left: at once with nothing corrected,
  /// otherwise once the card is written again. One that cannot be written
  /// asks whether to try again or to leave without the corrections. A card
  /// that had changed elsewhere stays on screen, read again.
  Future<bool> _mayLeave() async {
    final answers = widget.answers;
    if (!mounted || answers == null || !answers.hasPending) return true;
    if (_leaving) return false;
    setState(() => _leaving = true);
    try {
      while (true) {
        final rewrite = await _rewrite();
        if (!mounted) return true;
        switch (rewrite?.status) {
          case TasteCardRewriteStatus.failed:
            setState(() => _askingToRetry = true);
            final retry = await showAppDialog<bool>(
              context: context,
              dismissible: false,
              builder: (_) => const _RewriteFailedDialog(),
            );
            if (!mounted) return true;
            setState(() => _askingToRetry = false);
            if (retry == null) return false;
            if (retry) continue;
            answers.discard();
            return true;
          case TasteCardRewriteStatus.conflicted:
            showAppSnackBar(context, TasteCardAnswersEditor.conflictNotice);
            return false;
          default:
            return true;
        }
      }
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  /// A pop held back by the corrections goes on once [_mayLeave] allows.
  Future<void> _leave() async {
    if (!await _mayLeave() || !mounted) return;
    if (_router case final router?) {
      router.pop();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// 술결 한입 (기록한 술 · 별명 · 태그 · 잘 맞았던 이유 · 아쉬웠던 이유) →
  /// 다음 술 가이드 → 저장. A reason section with nothing to say is left out,
  /// heading and all.
  List<Widget> _buildSlivers(TasteCardSnapshotViewData viewData) {
    final reasons = <_Reasons>[
      if (viewData.positive.isNotEmpty)
        (key: 'positive', label: '좋았던 맛의 정체', paragraphs: viewData.positive),
      if (viewData.burden.isNotEmpty)
        (key: 'burden', label: '아쉬웠던 맛의 정체', paragraphs: viewData.burden),
      if (viewData.balanced.isNotEmpty)
        (key: 'balanced', label: '편안하게 다가왔던 이유', paragraphs: viewData.balanced),
    ];
    return <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: 22)),
      SliverToBoxAdapter(
        child: _BiteSection(
          bite: viewData.bite,
          reasons: reasons,
          product: viewData.product,
          recordedAt: viewData.recordedAt,
          recordPrice: widget.recordPrice,
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 28)),
      if ((widget.onOpenApp, widget.onSave) case (null, final onSave?))
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _CardActions(onSave: onSave),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 34)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final viewData = _viewData;
    final note = viewData.note;
    final card = CustomScrollView(
      key: const ValueKey<String>('onboarding-page-scroll'),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: _buildSlivers(viewData),
    );
    final page = DecoratedBox(
      decoration: const BoxDecoration(
        color: _TasteCardColors.canvas,
        image: DecorationImage(
          image: AssetImage(
            'assets/images/paper/next_drink_quote_card_background.png',
          ),
          fit: BoxFit.fitWidth,
          repeat: ImageRepeat.repeatY,
          opacity: .24,
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: <Widget>[
              if (note != null)
                _CardTabBar(selected: _tab, onSelect: _selectTab),
              Expanded(
                child: note == null
                    ? card
                    : IndexedStack(
                        index: _tab.index,
                        sizing: StackFit.expand,
                        children: <Widget>[
                          _TabPage(
                            active: _tab == _CardTab.card,
                            child: _rewriting ? const _CardRewriting() : card,
                          ),
                          _TabPage(
                            active: _tab == _CardTab.note,
                            child: _NoteSheet(
                              note: note,
                              product: viewData.product,
                              recordedAt: viewData.recordedAt,
                              recordPrice: widget.recordPrice,
                              entries: widget.noteEntries,
                              recordMemo: widget.recordMemo,
                              answers: widget.answers,
                            ),
                          ),
                        ],
                      ),
              ),
              if (widget.onOpenApp case final onOpenApp?)
                _OpenAppBar(onPressed: onOpenApp),
            ],
          ),
        ),
      ),
    );
    return PopScope<Object?>(
      // A swipe back cannot wait for the card to be written again, so it
      // is off while a correction waits; any other back is held for it.
      canPop: !_hasCorrections && !_leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Stack(
        children: <Widget>[
          page,
          if (_leaving && !_askingToRetry)
            const Positioned.fill(child: _LeaveHeld()),
        ],
      ),
    );
  }
}
