import '../../features/catalog/catalog_drink.dart';
import '../../features/onboarding/onboarding_entry_draft.dart';
import '../../features/taste_card/data/taste_card_submission_mapper.dart';
import '../../navigation/app_route.dart';
import '../state/onboarding_flow_state.dart';
import 'flow_host.dart';
import 'taste_card_coordinator.dart';

/// The first-record flow: drink search, the sensory questionnaire (opening
/// with the revisit judgment) and the result. A first record takes no photo
/// or note; those belong to the app's record flow, after the card.
class OnboardingCoordinator {
  OnboardingCoordinator(this._host, this._tasteCard);

  final FlowHost _host;
  final TasteCardCoordinator _tasteCard;
  final OnboardingFlowState state = OnboardingFlowState.initial();

  DrinkSelection get selectedDrink {
    if (!state.entryDraft.canContinue) {
      throw StateError('술 이름을 선택한 뒤에만 온보딩을 계속할 수 있습니다.');
    }
    return state.entryDraft.drinkSelection!;
  }

  void continueWithDrinkSelection(DrinkSelection selection) {
    _host.refresh(() {
      state.startWith(OnboardingEntryDraft.fromDrinkSelection(selection));
      _tasteCard.startNew(TasteCardViewContext.firstOnboarding);
    });
    _host.router.push(AppRoute.onboardingQuestions);
  }

  Future<void> submitTasteCard() {
    return _tasteCard.submit(
      context: TasteCardViewContext.firstOnboarding,
      requireAuthenticated: false,
      buildRequest: ({required idempotencyKey, anonymousSessionId}) =>
          TasteCardSubmissionMapper.fromSensoryFlow(
            idempotencyKey: idempotencyKey,
            anonymousSessionId: anonymousSessionId,
            selection: selectedDrink,
            flow: state.sensory.flow!,
            registry: state.sensory.data!.registry,
          ),
    );
  }

  void resetAfterSignOut() {
    state.resetEntry();
  }
}
