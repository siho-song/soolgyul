import 'package:flutter/material.dart';
import 'package:soolgyul/src/core/ids.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/onboarding/presentation/auth/profile_setup_screen.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/onboarding_actions.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/onboarding_buttons.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_draft.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_gateway.dart';
import 'package:soolgyul/src/features/profile/data/profile_setup_draft.dart';

import '../support/app_test_harness.dart';

final _validProfile = ProfileSetupDraft(
  displayName: '민지',
  interestedDrinkTypes: const {DrinkInterest.wine},
);

void main() {
  test('birth date validates leap days and sends date without timezone', () {
    final draft = const AccountCompletionDraft(
      birthYear: 2000,
      birthMonth: 2,
      birthDay: 29,
      gender: ProfileGender.female,
      adultAgeConfirmed: true,
      termsAccepted: true,
      privacyAccepted: true,
    );
    expect(draft.canComplete, isTrue);
    expect(draft.copyWith(birthYear: 2001).canComplete, isFalse);
    expect(draft.copyWith(birthMonth: 4, birthDay: 31).canComplete, isFalse);
    expect(draft.copyWith(clearBirthDay: true).canComplete, isFalse);
    final json = CompleteAccountRequest.fromDraft(
      idempotencyKey: createUuidV4(),
      displayName: '테스터',
      draft: draft,
    ).toJson();
    expect(json['birth_date'], '2000-02-29');
    expect(json['birth_year'], 2000);
  });
  test('gender is required and travels with the privacy agreement', () {
    final draft = AccountCompletionDraft(
      birthYear: 1990,
      birthMonth: 3,
      birthDay: 21,
      adultAgeConfirmed: true,
      termsAccepted: true,
      privacyAccepted: true,
    );
    Map<String, dynamic> body(AccountCompletionDraft value) =>
        CompleteAccountRequest.fromDraft(
          idempotencyKey: createUuidV4(),
          displayName: '테스터',
          draft: value,
        ).toJson();
    expect(draft.canComplete, isFalse);
    final withGender = draft.copyWith(gender: ProfileGender.female);
    expect(withGender.canComplete, isTrue);
    expect(body(withGender)['gender'], 'female');
    expect(body(withGender)['gender_consent_accepted'], isTrue);
    expect(withGender.copyWith(privacyAccepted: false).canComplete, isFalse);
  });

  test(
    'account completion requires an eligible year and required agreements',
    () {
      final incomplete = AccountCompletionDraft(
        birthYear: AccountCompletionDraft.latestEligibleBirthYear(),
        birthMonth: 1,
        birthDay: 1,
        gender: ProfileGender.other,
        adultAgeConfirmed: true,
        termsAccepted: true,
      );
      final complete = incomplete.copyWith(privacyAccepted: true);

      expect(incomplete.canComplete, isFalse);
      expect(complete.canComplete, isTrue);
      expect(complete.marketingOptIn, isFalse);
    },
  );

  test('account completion request pins policy versions and omits provider', () {
    final request = CompleteAccountRequest.fromDraft(
      idempotencyKey: createUuidV4(),
      displayName: '새사용자',
      draft: AccountCompletionDraft(
        birthYear: AccountCompletionDraft.latestEligibleBirthYear(),
        birthMonth: 1,
        birthDay: 1,
        gender: ProfileGender.male,
        adultAgeConfirmed: true,
        termsAccepted: true,
        privacyAccepted: true,
      ),
    );
    final body = request.toJson();

    expect(
      body['idempotency_key'],
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(body['terms_version'], AccountPolicyVersions.terms);
    expect(body['privacy_version'], AccountPolicyVersions.privacy);
    expect(body['marketing_version'], AccountPolicyVersions.marketing);
    expect(body, isNot(contains('auth_provider')));
  });

  testWidgets(
    'signup confirmation enables completion only after required input',
    (tester) async {
      var draft = const AccountCompletionDraft();
      var completions = 0;
      await pumpTestScreen(
        tester,
        StatefulBuilder(
          builder: (context, setState) => ProfileSetupScreen(
            profileDraft: _validProfile,
            onProfileChanged: (_) {},
            accountDraft: draft,
            onAccountChanged: (updated) => setState(() => draft = updated),
            onComplete: () => completions += 1,
            onOpenTerms: () {},
            onOpenPrivacy: () {},
          ),
        ),
      );

      expect(
        tester
            .widget<OnboardingPrimaryButton>(
              find.byKey(const ValueKey<String>('complete-signup-button')),
            )
            .onPressed,
        isNull,
      );

      await pickEligibleBirthDate(tester);
      await pickGender(tester);
      for (final key in <String>[
        'adult-agreement-row',
        'terms-agreement-row',
        'privacy-agreement-row',
      ]) {
        final row = find.byKey(ValueKey<String>(key));
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pump();
      }

      final completeButton = tester.widget<OnboardingPrimaryButton>(
        find.byKey(const ValueKey<String>('complete-signup-button')),
      );
      expect(completeButton.onPressed, isNotNull);
      expect(draft.marketingOptIn, isFalse);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('complete-signup-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('complete-signup-button')),
      );
      expect(completions, 1);
    },
  );

  testWidgets('all agreement includes the optional marketing choice', (
    tester,
  ) async {
    var draft = AccountCompletionDraft(
      birthYear: AccountCompletionDraft.latestEligibleBirthYear(),
      birthMonth: 1,
      birthDay: 1,
      gender: ProfileGender.male,
    );
    await pumpTestScreen(
      tester,
      StatefulBuilder(
        builder: (context, setState) => ProfileSetupScreen(
          profileDraft: _validProfile,
          onProfileChanged: (_) {},
          accountDraft: draft,
          onAccountChanged: (updated) => setState(() => draft = updated),
          onComplete: () {},
          onOpenTerms: () {},
          onOpenPrivacy: () {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('all-agreements-row')));
    await tester.pump();

    expect(draft.hasRequiredAgreements, isTrue);
    expect(draft.marketingOptIn, isTrue);
    expect(draft.canComplete, isTrue);
  });

  group('profile draft fields', () {
    Widget setupScreen({
      required ProfileSetupDraft draft,
      required ValueChanged<ProfileSetupDraft> onChanged,
      VoidCallback? onComplete,
    }) => ProfileSetupScreen(
      profileDraft: draft,
      onProfileChanged: onChanged,
      accountDraft: const AccountCompletionDraft(),
      onAccountChanged: (_) {},
      onComplete: onComplete ?? () {},
      onOpenTerms: () {},
      onOpenPrivacy: () {},
    );

    Future<ProfileSetupDraft Function()> pumpSetup(
      WidgetTester tester, {
      String displayName = '',
      VoidCallback? onComplete,
    }) async {
      var draft = ProfileSetupDraft(displayName: displayName);
      await pumpTestScreen(
        tester,
        StatefulBuilder(
          builder: (context, setState) => setupScreen(
            draft: draft,
            onChanged: (updatedDraft) => setState(() => draft = updatedDraft),
            onComplete: onComplete,
          ),
        ),
      );
      return () => draft;
    }

    testWidgets('the name field updates the draft', (tester) async {
      final draft = await pumpSetup(tester);

      await tester.enterText(find.byType(TextFormField), '민지');
      await tester.pump();

      expect(draft().displayName, '민지');
    });

    testWidgets('the name field rejects characters outside the backend '
        'contract', (tester) async {
      final draft = await pumpSetup(tester);

      await tester.enterText(find.byType(TextFormField), '👨‍👩‍👧‍👦👩‍👩‍👦');
      await tester.pump();

      expect(draft().displayName, isEmpty);
      expect(find.text('0/12자'), findsOneWidget);
    });

    testWidgets('drink-interest tiles update the draft', (tester) async {
      final draft = await pumpSetup(tester, displayName: '민지');

      await tester.tap(find.text('와인'));
      await tester.pump();

      expect(draft().interestedDrinkTypes, contains(DrinkInterest.wine));
      expect(find.byType(OnboardingDrinkTile), findsNWidgets(4));
      expect(find.text('사케'), findsOneWidget);
      for (final absent in ['쇼추', '리큐르', '중국술', '맥주', '칵테일']) {
        expect(find.text(absent), findsNothing);
      }
    });
  });
}
