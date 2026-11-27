import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/errors/error_report.dart';
import '../../../../core/sensory/sensory_question_flow.dart';
import '../../../../widgets/app_snack_bar.dart';
import '../../../onboarding/data/sensory_questionnaire_data.dart';
import '../../data/sensory_submission.dart';
import '../../data/taste_card_answers_gateway.dart';
import '../../data/taste_card_gateway.dart';
import '../../data/taste_card_note_redraw.dart';
import '../../data/taste_card_note_view_data.dart';
import '../../data/taste_card_result.dart';

/// How writing the card again ended.
enum TasteCardRewriteStatus {
  /// No answer was waiting to be sent.
  unchanged,

  /// The server wrote the card again.
  written,

  /// The card had changed elsewhere: the corrections were dropped and the
  /// card read again.
  conflicted,

  /// The corrections could not be sent and are still waiting.
  failed,
}

/// What [TasteCardAnswersEditor.flush] ended with.
class TasteCardRewrite {
  const TasteCardRewrite(this.status, [this.card, this.error]);

  final TasteCardRewriteStatus status;

  /// What a failed write failed with.
  final Object? error;

  /// The card the server wrote, or the one read again after a conflict;
  /// null otherwise, and when it could not be read again.
  final TasteCardResult? card;
}

/// The answers behind the saved card on screen, which its owner corrects
/// on the 테이스팅 노트's form. The stored answers are read when the form
/// opens. What the form keeps on 완료 is kept here, not sent: the note
/// redraws those parts itself, and [flush] has the server write the card
/// again from every correction at once.
class TasteCardAnswersEditor extends ChangeNotifier {
  TasteCardAnswersEditor({
    required this.resultId,
    required this.gateway,
    required this.loadQuestions,
    this.onRewritten,
  });

  final String resultId;
  final TasteCardAnswersGateway gateway;

  /// Reads the questionnaire of the record's drink: the aromas, and the
  /// gauges its kind is asked.
  final Future<SensoryQuestionnaireData> Function() loadQuestions;

  /// Called with the card once it is written again, or read again after a
  /// conflict, so lists that show the card reload.
  final ValueChanged<TasteCardResult>? onRewritten;

  /// What a card that could not be written again is told with: the
  /// connection's wording for a connection failure.
  static String rewriteFailure(Object? error) =>
      failureLine(error, '고친 답을 반영하지 못했어요. 다시 시도해 주세요.');
  static const conflictNotice = '다른 기기에서 바뀐 기록이라 새로 불러왔어요.';
  static const _loadFailure = '답을 불러오지 못했어요. 다시 시도해 주세요.';
  static const _notRevisable = '이 기록은 답을 고칠 수 없어요.';

  /// What the server holds; null until read.
  TasteCardAnswers? _stored;
  SensoryQuestionnaireData? _questions;

  /// The questions answered again since the card was last written, by
  /// question key.
  final _pending = <String, List<String>>{};

  /// The write on its way, which a second call waits for.
  Future<TasteCardRewrite>? _flushing;
  bool _disposed = false;

  /// Whether any correction waits to be sent.
  bool get hasPending => _pending.isNotEmpty;

  /// The chosen option ids of [questionKey]: the correction when there is
  /// one, else what is stored; none before the answers are read.
  List<String> answersOf(String questionKey) =>
      _pending[questionKey] ?? _stored?.answers[questionKey] ?? const [];

  /// [note] with the corrected parts drawn from their answers.
  TasteCardNoteViewData redrawn(TasteCardNoteViewData note) {
    final questions = _questions;
    return questions == null
        ? note
        : redrawNote(
            note,
            _pending,
            gauges: questions.gauges,
            aromaLabel: questions.registry.aromaLabel,
          );
  }

  /// The questionnaire of the record's drink, once read.
  SensoryQuestionnaireData? get questions => _questions;

  /// The record's answers as they stand, corrections included, in a flow
  /// of the whole questionnaire for the note's form to change; null, with
  /// a notice of why, when they cannot be corrected. [note] is the card's
  /// note, whose words a corrected part is redrawn with: a note without
  /// them, like a record answered under an older questionnaire, cannot be.
  Future<SensoryQuestionFlow?> startFlow(
    BuildContext context,
    TasteCardNoteViewData note,
  ) async {
    if (!await _correctable(context, note)) return null;
    final questions = _questions!;
    final flow = questions.registry.createFlow(questions.gauges);
    questions.registry.restoreAnswers(flow, <String>[
      for (final key in SensorySubmission.questionKeys) ...answersOf(key),
    ]);
    return flow;
  }

  /// Whether the record's answers can be corrected, with them and the
  /// questionnaire read; says why not otherwise.
  Future<bool> _correctable(
    BuildContext context,
    TasteCardNoteViewData note,
  ) async {
    if (note.words == null) {
      showAppSnackBar(context, _notRevisable);
      return false;
    }
    final failure = await _load();
    if (!context.mounted) return false;
    final stored = _stored;
    if (failure != null || stored == null || _questions == null) {
      showAppSnackBar(context, failureLine(failure, _loadFailure));
      return false;
    }
    if (!stored.revisable) {
      showAppSnackBar(context, _notRevisable);
      return false;
    }
    return true;
  }

  /// Reads the stored answers and the questionnaire, as far as they have
  /// not been read. Gives what the reading failed with, or null.
  Future<Object?> _load() async {
    try {
      final loaded = await Future.wait<Object>(<Future<Object>>[
        Future<Object>.sync(() => _stored ?? gateway.loadAnswers(resultId)),
        Future<Object>.sync(() => _questions ?? loadQuestions()),
      ]);
      if (_disposed) return null;
      _stored = loaded[0] as TasteCardAnswers;
      _questions = loaded[1] as SensoryQuestionnaireData;
      return null;
    } catch (error, stack) {
      // The notice names only a dead connection; the report says the rest.
      // The next tap reads them again.
      reportError(error, stack, where: 'card answers');
      return error;
    }
  }

  /// Keeps [answered], questions by key, as corrections; one answered as
  /// it is stored is none.
  void keep(Map<String, List<String>> answered) {
    if (_disposed) return;
    for (final MapEntry(:key, :value) in answered.entries) {
      if (_sameAnswers(value, _stored?.answers[key] ?? const [])) {
        _pending.remove(key);
      } else {
        _pending[key] = value;
      }
    }
    notifyListeners();
  }

  /// Has the server write the card again from the corrections, all in one
  /// request. A failure leaves them waiting; a conflict drops them.
  Future<TasteCardRewrite> flush() =>
      _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<TasteCardRewrite> _flush() async {
    if (_pending.isEmpty) {
      return const TasteCardRewrite(TasteCardRewriteStatus.unchanged);
    }
    final sent = Map<String, List<String>>.of(_pending);
    final TasteCardResult card;
    try {
      card = await gateway.reviseAnswers(resultId, sent);
    } on TasteCardGatewayException catch (error) {
      return error.code == 'revision_conflict'
          ? _reload()
          : TasteCardRewrite(TasteCardRewriteStatus.failed, null, error);
    } catch (error, stack) {
      reportError(error, stack, where: 'card answers');
      return TasteCardRewrite(TasteCardRewriteStatus.failed, null, error);
    }
    _stored = TasteCardAnswers(
      revisable: true,
      answers: <String, List<String>>{...?_stored?.answers, ...sent},
    );
    // A question answered yet again meanwhile is still a correction.
    _pending.removeWhere(
      (key, value) => sent.containsKey(key) && _sameAnswers(value, sent[key]!),
    );
    _announce(card);
    return TasteCardRewrite(TasteCardRewriteStatus.written, card);
  }

  /// The card changed elsewhere since it was read: the corrections go, and
  /// the card and its answers are read again.
  Future<TasteCardRewrite> _reload() async {
    _pending.clear();
    // Read again by the next sheet when it cannot be read now.
    _stored = null;
    TasteCardResult? card;
    try {
      card = await gateway.fetchOwnedResult(resultId);
      _stored = await gateway.loadAnswers(resultId);
    } catch (_) {
      // What was read stands.
    }
    _announce(card);
    return TasteCardRewrite(TasteCardRewriteStatus.conflicted, card);
  }

  void _announce(TasteCardResult? card) {
    if (_disposed) return;
    notifyListeners();
    if (card != null) onRewritten?.call(card);
  }

  /// Drops the corrections that were not sent.
  void discard() {
    if (_disposed || _pending.isEmpty) return;
    _pending.clear();
    notifyListeners();
  }

  /// Whether two answers choose the same options; their order says nothing.
  static bool _sameAnswers(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
