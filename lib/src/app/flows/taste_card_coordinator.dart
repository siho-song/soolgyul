import '../../features/taste_card/data/taste_card_gateway.dart';
import '../../features/taste_card/data/taste_card_wire_requests.dart';
import '../../features/taste_card/data/taste_card_result.dart';
import '../../navigation/app_route.dart';
import '../state/sensory_session.dart';
import '../state/taste_card_flow_state.dart';
import 'app_gateways.dart';
import 'flow_host.dart';
import '../../core/ids.dart';

/// Which record the result route currently shows.
enum TasteCardViewContext { firstOnboarding, repeatRecord }

typedef TasteCardRequestBuilder =
    CreateTasteCardResultRequest Function({
      required String idempotencyKey,
      String? anonymousSessionId,
    });

/// Owns one taste card submission at a time: creating it, retrying it and
/// claiming a web card's ticket for the account. Onboarding and repeat
/// records both submit through here.
class TasteCardCoordinator {
  TasteCardCoordinator(this._host, this._gateways, {this.onRecordSaved});

  final FlowHost _host;
  final AppGateways _gateways;

  /// Called when a new record lands in the account (made or claimed).
  final void Function()? onRecordSaved;
  final TasteCardFlowState state = TasteCardFlowState();
  TasteCardViewContext viewContext = TasteCardViewContext.firstOnboarding;

  /// Whether the result route shows a card opened from a list of saved ones
  /// (not one just made), which its owner may delete.
  bool showsSavedCard = false;

  /// Bumped whenever user input changes so a stale response is dropped.
  int _inputRevision = 0;
  Future<void> Function()? _lastSubmission;

  TasteCardGateway? get gateway => _gateways.tasteCard;

  /// Starts a fresh submission for [context]; call inside `refresh`.
  void startNew(TasteCardViewContext context) {
    _inputRevision++;
    state.startNewSubmission();
    viewContext = context;
    showsSavedCard = false;
  }

  /// Forgets the current submission without changing the view context.
  void reset() {
    _inputRevision++;
    state.startNewSubmission();
  }

  /// Marks the current input as changed so an in-flight result is ignored.
  void invalidateInput() {
    _inputRevision++;
    if (state.idempotencyKey != null) state.startNewSubmission();
  }

  void noteSensoryAnswersChanged(SensorySession session) {
    final fingerprint = session.currentFingerprint();
    _host.refresh(() {
      if (session.fingerprint != fingerprint) invalidateInput();
      session.fingerprint = fingerprint;
    });
  }

  /// Submits a record and shows the result route while it is pending.
  ///
  /// With no gateway the result route shows the local fixture (onboarding)
  /// or the flow returns home (repeat record). [requireAuthenticated]
  /// records fail closed for anonymous sessions instead of submitting.
  Future<void> submit({
    required TasteCardViewContext context,
    required bool requireAuthenticated,
    required TasteCardRequestBuilder buildRequest,
  }) async {
    final gateway = _gateways.tasteCard;
    if (gateway == null) {
      if (requireAuthenticated) {
        _host.router.replaceRoot(AppRoute.home);
      } else {
        _host.router.push(AppRoute.onboardingResult);
      }
      return;
    }
    _lastSubmission = () => submit(
      context: context,
      requireAuthenticated: requireAuthenticated,
      buildRequest: buildRequest,
    );
    if (requireAuthenticated && !gateway.isAuthenticated) {
      _host.refresh(() {
        viewContext = context;
        state.markFailure();
      });
      _host.router.push(AppRoute.onboardingResult);
      return;
    }
    final started = state.beginSubmission(
      createId: createUuidV4,
      isAuthenticated: gateway.isAuthenticated,
    );
    if (!started) return;
    final revision = _inputRevision;
    _host.refresh(() => viewContext = context);
    if (_host.router.currentRoute != AppRoute.onboardingResult) {
      _host.router.push(AppRoute.onboardingResult);
    }
    try {
      final outcome = await gateway.create(
        buildRequest(
          idempotencyKey: state.idempotencyKey!,
          anonymousSessionId: gateway.isAuthenticated
              ? null
              : state.anonymousSessionId,
        ),
      );
      if (!_host.mounted || revision != _inputRevision) return;
      _host.refresh(() {
        switch (outcome) {
          case TasteCardFinalOutcome(:final result):
            state.markFinal(result);
          case TasteCardRetryableOutcome():
            state.markRetryable();
        }
      });
      if (outcome case TasteCardFinalOutcome(
        :final result,
      ) when result.isSaved) {
        onRecordSaved?.call();
      }
    } catch (_) {
      if (_host.mounted && revision == _inputRevision) {
        _host.refresh(state.markFailure);
      }
    }
  }

  /// Shows a saved card of the signed-in account on the result route, as the
  /// home's 다음 한 잔 가이드 opens the card a slide came from.
  Future<void> open(String resultId) async {
    final gateway = _gateways.tasteCard;
    if (gateway == null || !gateway.isAuthenticated) return;
    _lastSubmission = () => open(resultId);
    _host.refresh(() {
      startNew(TasteCardViewContext.repeatRecord);
      showsSavedCard = true;
      state.phase = TasteCardFlowPhase.submitting;
    });
    final revision = _inputRevision;
    if (_host.router.currentRoute != AppRoute.onboardingResult) {
      _host.router.push(AppRoute.onboardingResult);
    }
    try {
      final result = await gateway.fetchOwnedResult(resultId);
      if (!_host.mounted || revision != _inputRevision) return;
      _host.refresh(() => state.markFinal(result));
    } catch (_) {
      if (_host.mounted && revision == _inputRevision) {
        _host.refresh(state.markFailure);
      }
    }
  }

  /// Deletes the record behind the saved card on screen. Throws when the
  /// server refuses; the card stays on screen then.
  Future<void> deleteShownCard() async {
    final gateway = _gateways.tasteCard;
    final resultId = state.result?.resultId;
    if (gateway == null || resultId == null || !showsSavedCard) return;
    await gateway.deleteOwnedResult(resultId);
    _host.refresh(() => startNew(TasteCardViewContext.repeatRecord));
  }

  /// Retries the last submission from the result route.
  Future<void> retry() async {
    await _lastSubmission?.call();
  }

  /// Claims a card made on the web for the signed-in account; the result
  /// route shows it as saved, or the retry when the claim failed.
  Future<void> claim(TasteCardPendingConversion ticket) async {
    final gateway = _gateways.tasteCard;
    if (gateway == null || !gateway.isAuthenticated) return;
    _lastSubmission = () => claim(ticket);
    _host.refresh(() {
      startNew(TasteCardViewContext.firstOnboarding);
      state.beginSubmission(createId: createUuidV4, isAuthenticated: true);
    });
    final revision = _inputRevision;
    try {
      final saved = await gateway.convert(
        AnonymousTasteCardConversionRequest(
          anonymousSessionId: ticket.anonymousSessionId,
          resultId: ticket.resultId,
          conversionToken: ticket.conversionToken,
          idempotencyKey: state.idempotencyKey!,
        ),
      );
      if (!_host.mounted || revision != _inputRevision) return;
      if (saved.resultId != ticket.resultId ||
          saved.snapshotRef != ticket.snapshotRef ||
          !saved.isSaved) {
        throw const TasteCardGatewayException(
          TasteCardGatewayOperation.convert,
          code: 'converted_snapshot_mismatch',
        );
      }
      _host.refresh(() => state.markFinal(saved));
      onRecordSaved?.call();
    } catch (_) {
      if (_host.mounted && revision == _inputRevision) {
        _host.refresh(state.markFailure);
      }
    }
  }

  /// The primary action on a saved result: home. The web's anonymous card
  /// has no save; its result sends the visitor to the app instead.
  void save() {
    if (state.result?.isSaved == true) {
      _host.router.replaceRoot(AppRoute.home);
    }
  }
}
