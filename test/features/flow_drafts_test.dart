import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/state/onboarding_flow_state.dart';
import 'package:soolgyul/src/app/state/record_flow_state.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/onboarding/data/onboarding_entry_draft.dart';
import 'package:soolgyul/src/features/profile/data/drink_interest_catalog.dart';
import 'package:soolgyul/src/features/profile/data/profile_setup_draft.dart';

const _glenfiddich = DrinkSelection.catalogMatch(
  CatalogDrink(
    id: 'whisky-glenfiddich-15',
    displayName: '글렌피딕 15년',
    category: DrinkCategory.whisky,
  ),
);
const _blank = DrinkSelection.catalogMatch(
  CatalogDrink(id: 'blank', displayName: '   ', category: DrinkCategory.whisky),
);

void main() {
  group('flow states', () {
    test('onboarding and record states reset their own drafts', () {
      final onboarding = OnboardingFlowState.initial();
      onboarding.startWith(
        OnboardingEntryDraft.fromDrinkSelection(_glenfiddich),
      );
      onboarding.updateProfile(
        ProfileSetupDraft(
          displayName: '민지',
          interestedDrinkTypes: const <DrinkInterest>[DrinkInterest.wine],
        ),
      );
      expect(onboarding.entryDraft.drinkName, '글렌피딕 15년');
      expect(onboarding.profileSetupDraft.displayName, '민지');

      onboarding.resetEntry();
      expect(onboarding.entryDraft.drinkName, isNull);
      expect(onboarding.profileSetupDraft.displayName, isEmpty);
      expect(onboarding.profileSetupDraft.interestedDrinkTypes, isEmpty);

      final record = RecordFlowState.initial();
      record.continueWithDrinkSelection(_glenfiddich);
      expect(record.drinkSelection?.catalogId, 'whisky-glenfiddich-15');
      record.reset();
      expect(record.drinkSelection, isNull);
    });

    test('a blank drink name is refused by both flows', () {
      final record = RecordFlowState.initial();
      expect(
        () => record.continueWithDrinkSelection(_blank),
        throwsArgumentError,
      );
      expect(record.drinkSelection, isNull);
      expect(
        () => OnboardingEntryDraft.fromDrinkSelection(_blank),
        throwsArgumentError,
      );
    });
  });

  group('OnboardingEntryDraft', () {
    test('requires a catalog drink for onboarding', () {
      final draft = OnboardingEntryDraft.fromDrinkSelection(
        const DrinkSelection.catalogMatch(
          CatalogDrink(
            id: 'whisky-1',
            displayName: '발베니 12년',
            category: DrinkCategory.whisky,
          ),
        ),
      );

      expect(draft.canContinue, isTrue);
      expect(draft.drinkName, '발베니 12년');
      expect(draft.drinkSelection?.catalogId, 'whisky-1');
      expect(const OnboardingEntryDraft.fromFeelingOnly().canContinue, isFalse);
    });
  });

  group('ProfileSetupDraft', () {
    test('normalizes the nickname and keeps the latest interest set', () {
      final draft = ProfileSetupDraft(
        displayName: '  민지  ',
        interestedDrinkTypes: <DrinkInterest>{
          DrinkInterest.wine,
          DrinkInterest.whisky,
          DrinkInterest.koreanTraditional,
          DrinkInterest.sake,
        },
      );

      expect(draft.displayName, '민지');
      expect(draft.hasValidDisplayName, isTrue);
      expect(draft.interestedDrinkTypes, hasLength(4));
    });

    test('every interest group can be selected at once', () {
      var draft = ProfileSetupDraft(displayName: '민지');
      for (final interest in DrinkInterest.values) {
        draft = draft.toggleDrinkInterest(interest);
      }
      expect(draft.interestedDrinkTypes, DrinkInterest.values.toSet());
      expect(draft.hasValidDrinkInterests, isTrue);
    });

    test('matches the backend nickname character and length contract', () {
      expect(
        ProfileSetupDraft(displayName: '1234567890123').hasValidDisplayName,
        isFalse,
      );
      expect(ProfileSetupDraft(displayName: '한').hasValidDisplayName, isFalse);
      expect(
        ProfileSetupDraft(displayName: '공백 이름').hasValidDisplayName,
        isFalse,
      );
      expect(
        ProfileSetupDraft(displayName: '👨‍👩‍👧‍👦').hasValidDisplayName,
        isFalse,
      );
      expect(ProfileSetupDraft(displayName: '민지2').hasValidDisplayName, isTrue);
    });

    test('toggles a drink interest without sharing mutable sets', () {
      final original = ProfileSetupDraft(displayName: '민지');
      final selected = original.toggleDrinkInterest(DrinkInterest.sake);

      expect(original.interestedDrinkTypes, isEmpty);
      expect(original.hasValidDrinkInterests, isFalse);
      expect(selected.interestedDrinkTypes, contains(DrinkInterest.sake));
      expect(selected.hasValidDrinkInterests, isTrue);
    });
  });

  group('drink interest catalog', () {
    test('관심 주종 카탈로그가 DB 표현 그룹과 1:1로 매핑된다', () {
      expect(
        drinkInterestOptions.map((option) => option.value).toList(),
        DrinkInterest.values,
      );
      expect(
        drinkInterestOptions.map((option) => option.wireKey).toList(),
        <String>['wine', 'whisky', 'korean_traditional', 'sake'],
      );
      expect(
        drinkInterestOptions.map((option) => option.label).toSet(),
        hasLength(DrinkInterest.values.length),
      );
    });

    test('모든 관심 주종에 표시 이미지가 연결되어 있다', () {
      for (final option in drinkInterestOptions) {
        final assetPath = option.assetPath;
        expect(assetPath, isNotNull, reason: '${option.wireKey} 이미지 경로 누락');
        expect(
          File(assetPath!).existsSync(),
          isTrue,
          reason: '${option.wireKey} 이미지 파일 누락: $assetPath',
        );
      }
    });
  });
}
