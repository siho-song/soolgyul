import '../../features/catalog/catalog_drink.dart';
import '../../features/taste_card/data/taste_card_submission_mapper.dart';
import '../../navigation/app_route.dart';
import '../state/record_flow_state.dart';
import 'flow_host.dart';
import 'taste_card_coordinator.dart';

/// The signed-in repeat record flow: drink search, the sensory questionnaire
/// and the submitted result. The photo and the one-line note are added from
/// the result card, after the record exists.
class RecordCoordinator {
  RecordCoordinator(this._host, this._tasteCard);

  final FlowHost _host;
  final TasteCardCoordinator _tasteCard;
  final RecordFlowState state = RecordFlowState.initial();

  /// Starts a new record from a main tab and returns there on completion.
  void startFlow() {
    final current = _host.router.currentRoute;
    final returnRoute = switch (current) {
      AppRoute.home ||
      AppRoute.preference ||
      AppRoute.explore ||
      AppRoute.profile => current,
      _ => AppRoute.home,
    };
    _host.refresh(() {
      state.reset();
      _tasteCard.startNew(TasteCardViewContext.repeatRecord);
    });
    _host.router.replaceStack(<AppRoute>[returnRoute, AppRoute.recordSearch]);
  }

  /// Starts a new record with [selection] already chosen, from any screen.
  void startFlowWith(DrinkSelection selection) {
    _host.refresh(() {
      state.reset();
      _tasteCard.startNew(TasteCardViewContext.repeatRecord);
    });
    continueWithDrinkSelection(selection);
  }

  void continueWithDrinkSelection(DrinkSelection selection) {
    _host.refresh(() {
      _tasteCard.invalidateInput();
      state.continueWithDrinkSelection(selection);
    });
    _host.router.push(AppRoute.recordQuestions);
  }

  Future<void> submitTasteCard() {
    return _tasteCard.submit(
      context: TasteCardViewContext.repeatRecord,
      requireAuthenticated: true,
      buildRequest: ({required idempotencyKey, anonymousSessionId}) =>
          TasteCardSubmissionMapper.fromSensoryFlow(
            idempotencyKey: idempotencyKey,
            anonymousSessionId: null,
            selection: state.drinkSelection!,
            flow: state.sensory.flow!,
            registry: state.sensory.data!.registry,
          ),
    );
  }

  void resetAfterSignOut() {
    state.reset();
  }
}
