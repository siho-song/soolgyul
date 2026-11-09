import '../../features/catalog/data/catalog_drink.dart';
import 'sensory_session.dart';

class RecordFlowState {
  RecordFlowState.initial();

  DrinkSelection? drinkSelection;
  final SensorySession sensory = SensorySession();

  void reset() {
    sensory.clear();
    drinkSelection = null;
  }

  void continueWithDrinkSelection(DrinkSelection selection) {
    if (selection.displayName.trim().isEmpty) {
      throw ArgumentError.value(
        selection.displayName,
        'selection',
        '술 이름은 필수입니다.',
      );
    }
    sensory.clear();
    drinkSelection = selection;
  }
}
