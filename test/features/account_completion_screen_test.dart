import 'package:soolgyul/src/core/catalog/drink_type.dart';
import 'package:flutter/material.dart';
import 'package:soolgyul/src/core/ids.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/onboarding/presentation/auth/profile_setup_screen.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/onboarding_actions.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/onboarding_buttons.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_draft.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_gateway.dart';
import 'package:soolgyul/src/features/profile/data/profile_setup_draft.dart';
import 'package:soolgyul/src/widgets/app_button.dart';

import '../support/app_test_harness.dart';

final _validProfile = ProfileSetupDraft(
  displayName: '민지',
  interestedDrinkTypes: const {DrinkType.wine},
);

/// Pumps the setup screen with a valid profile around [initial] and returns
/// the account draft as the screen last reported it.
Future<AccountCompletionDraft Function()> pumpAccountSetup(
  WidgetTester tester,
  AccountCompletionDraft initial, {
  VoidCallback? onComplete,
}) async {
  var draft = initial;
  await pumpTestScreen(
    tester,
    StatefulBuilder(
      builder: (context, setState) => ProfileSetupScreen(
        profileDraft: _validProfile,
        onProfileChanged: (_) {},
        accountDraft: draft,
        onAccountChanged: (updated) => setState(() => draft = updated),
        onComplete: onComplete ?? () {},
        onOpenTerms: () {},
        onOpenPrivacy: () {},
      ),
    ),
  );
  return () => draft;
}

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
      var completions = 0;
      final draft = await pumpAccountSetup(
        tester,
        const AccountCompletionDraft(),
        onComplete: () => completions += 1,
      );
      final next = find.byKey(
        const ValueKey<String>('profile-setup-next-button'),
      );
      final start = find.byKey(
        const ValueKey<String>('complete-signup-button'),
      );

      // The agreements are not asked before the birth date and gender.
      expect(tester.widget<OnboardingPrimaryButton>(next).onPressed, isNull);

      await pickEligibleBirthDate(tester);
      await pickGender(tester);
      expect(start, findsNothing);
      await showNextSetupStep(tester);
      expect(tester.widget<AppButton>(start).onPressed, isNull);
      await checkSetupAgreements(tester);

      expect(tester.widget<AppButton>(start).onPressed, isNotNull);
      expect(draft().marketingOptIn, isFalse);

      await tester.tap(start);
      expect(completions, 1);
    },
  );

  testWidgets('all agreement includes the optional marketing choice', (
    tester,
  ) async {
    final draft = await pumpAccountSetup(
      tester,
      AccountCompletionDraft(
        birthYear: AccountCompletionDraft.latestEligibleBirthYear(),
        birthMonth: 1,
        birthDay: 1,
        gender: ProfileGender.male,
      ),
    );
    await showNextSetupStep(tester);
    expect(find.text('[선택] 광고성 정보 앱 알림 수신 동의'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('all-agreements-row')));
    await tester.pumpAndSettle();

    expect(draft().hasRequiredAgreements, isTrue);
    expect(draft().marketingOptIn, isTrue);
    expect(draft().canComplete, isTrue);
  });

  testWidgets('closing the agreements sheet leaves the page as it was, and '
      'the checks are there when it opens again', (tester) async {
    await pumpAccountSetup(
      tester,
      AccountCompletionDraft(
        birthYear: AccountCompletionDraft.latestEligibleBirthYear(),
        birthMonth: 1,
        birthDay: 1,
        gender: ProfileGender.male,
      ),
    );
    final all = find.byKey(const ValueKey<String>('all-agreements-row'));
    bool checked() => tester
        .widget<Checkbox>(
          find.descendant(of: all, matching: find.byType(Checkbox)),
        )
        .value!;

    await showNextSetupStep(tester);
    expect(checked(), isFalse);
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(checked(), isTrue);

    // A tap above the sheet closes it.
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(all, findsNothing);
    expect(find.text('관심 있는 주종을 골라 주세요'), findsOneWidget);
    expect(find.text('다음'), findsOneWidget);

    await showNextSetupStep(tester);
    expect(checked(), isTrue);
  });

  testWidgets('while the save runs the sheet is busy; a save that fails '
      'leaves it open, says so, and takes another press', (tester) async {
    var submitting = false;
    var completions = 0;
    late StateSetter setHost;
    var account = AccountCompletionDraft(
      birthYear: AccountCompletionDraft.latestEligibleBirthYear(),
      birthMonth: 1,
      birthDay: 1,
      gender: ProfileGender.male,
    );
    await pumpTestScreen(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          setHost = setState;
          return ProfileSetupScreen(
            profileDraft: _validProfile,
            onProfileChanged: (_) {},
            accountDraft: account,
            onAccountChanged: (updated) => setState(() => account = updated),
            onComplete: () => setState(() {
              completions += 1;
              submitting = true;
            }),
            onOpenTerms: () {},
            onOpenPrivacy: () {},
            submitting: submitting,
          );
        },
      ),
    );
    final start = find.byKey(const ValueKey<String>('complete-signup-button'));
    await showNextSetupStep(tester);
    await checkSetupAgreements(tester);
    await startFromSetupAgreements(tester);

    // Busy: neither the button nor a row takes another press.
    expect(find.text('가입하는 중...'), findsWidgets);
    expect(tester.widget<AppButton>(start).onPressed, isNull);
    await tester.tap(start, warnIfMissed: false);
    await tester.tap(
      find.byKey(const ValueKey<String>('adult-agreement-row')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(completions, 1);
    expect(account.adultAgeConfirmed, isTrue);

    // The save did not go through: the page is still here.
    final failure = find.byKey(
      const ValueKey<String>('profile-setup-save-feedback'),
    );
    expect(failure, findsNothing);
    setHost(() => submitting = false);
    await tester.pumpAndSettle();
    expect(failure, findsOneWidget);
    expect(find.text('술결 시작하기'), findsOneWidget);
    expect(tester.widget<AppButton>(start).onPressed, isNotNull);

    await startFromSetupAgreements(tester);
    expect(completions, 2);
    expect(failure, findsNothing);
  });

  group('one question at a time', () {
    /// A fresh page whose drafts the test host keeps.
    Future<void> pumpFresh(WidgetTester tester) async {
      var profile = ProfileSetupDraft(displayName: '');
      var account = const AccountCompletionDraft();
      await pumpTestScreen(
        tester,
        StatefulBuilder(
          builder: (context, setState) => ProfileSetupScreen(
            profileDraft: profile,
            onProfileChanged: (updated) => setState(() => profile = updated),
            accountDraft: account,
            onAccountChanged: (updated) => setState(() => account = updated),
            onComplete: () {},
            onOpenTerms: () {},
            onOpenPrivacy: () {},
          ),
        ),
      );
    }

    final nickname = find.byType(TextFormField);
    final birthDate = find.byKey(const ValueKey<String>('birth-date-field'));
    final agreements = find.byKey(const ValueKey<String>('all-agreements-row'));

    testWidgets('the one being asked is on top, the answered ones under it, '
        'the newest first, and the agreements come in a sheet', (tester) async {
      await pumpFresh(tester);
      double top(Finder finder) => tester.getTopLeft(finder).dy;

      // Only the nickname at first, with the keyboard already on it.
      expect(find.text('닉네임을 알려 주세요'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(birthDate, findsNothing);
      expect(find.text('와인'), findsNothing);

      // The keyboard's done key moves on as 다음 does.
      await tester.enterText(nickname, '민지');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await pickEligibleBirthDate(tester);
      expect(find.text('생년월일과 성별을 알려 주세요'), findsOneWidget);
      expect(top(birthDate), lessThan(top(nickname)));
      expect(find.text('와인'), findsNothing);

      // Both pickers answered bring the interests without a press.
      await pickGender(tester);
      expect(find.text('관심 있는 주종을 골라 주세요'), findsOneWidget);
      expect(top(find.text('와인')), lessThan(top(birthDate)));
      expect(top(birthDate), lessThan(top(nickname)));
      expect(agreements, findsNothing);

      await tester.tap(find.text('와인'));
      await tester.pump();
      await showNextSetupStep(tester);
      expect(find.text('약관에 동의해 주세요'), findsOneWidget);
      expect(agreements, findsOneWidget);
      expect(find.text('술결 시작하기'), findsOneWidget);
      // The page under the sheet still asks its last question.
      expect(find.text('관심 있는 주종을 골라 주세요'), findsOneWidget);
    });

    testWidgets('the birth date picker opens by itself when its step '
        'appears, and only then', (tester) async {
      await pumpFresh(tester);
      await tester.enterText(nickname, '민지');
      await tester.pump();
      expect(find.byType(DatePickerDialog), findsNothing);

      await showNextSetupStep(tester);
      expect(find.byType(DatePickerDialog), findsOneWidget);

      // Closed without a date, it waits for a press on the field.
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      await tester.enterText(nickname, '민지야');
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(birthDate, findsOneWidget);

      await tester.tap(birthDate);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('a page opened with a draft starts where the draft stops', (
      tester,
    ) async {
      // Interests chosen, the nickname still missing: the nickname is asked.
      await pumpTestScreen(
        tester,
        ProfileSetupScreen(
          profileDraft: ProfileSetupDraft(
            displayName: '',
            interestedDrinkTypes: const {DrinkType.wine},
          ),
          onProfileChanged: (_) {},
          accountDraft: const AccountCompletionDraft(),
          onAccountChanged: (_) {},
          onComplete: () {},
          onOpenTerms: () {},
          onOpenPrivacy: () {},
        ),
      );
      expect(find.text('닉네임을 알려 주세요'), findsOneWidget);
      expect(birthDate, findsNothing);

      // A birth date picked before: its step is asked, and the picker
      // stays closed.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpTestScreen(
        tester,
        ProfileSetupScreen(
          profileDraft: ProfileSetupDraft(displayName: '민지'),
          onProfileChanged: (_) {},
          accountDraft: AccountCompletionDraft(
            birthYear: AccountCompletionDraft.latestEligibleBirthYear(),
            birthMonth: 1,
            birthDay: 1,
          ),
          onAccountChanged: (_) {},
          onComplete: () {},
          onOpenTerms: () {},
          onOpenPrivacy: () {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('생년월일과 성별을 알려 주세요'), findsOneWidget);
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.text('와인'), findsNothing);
    });
  });

  group('profile draft fields', () {
    Widget setupScreen({
      required ProfileSetupDraft draft,
      required ValueChanged<ProfileSetupDraft> onChanged,
      AccountCompletionDraft account = const AccountCompletionDraft(),
      VoidCallback? onComplete,
    }) => ProfileSetupScreen(
      profileDraft: draft,
      onProfileChanged: onChanged,
      accountDraft: account,
      onAccountChanged: (_) {},
      onComplete: onComplete ?? () {},
      onOpenTerms: () {},
      onOpenPrivacy: () {},
    );

    Future<ProfileSetupDraft Function()> pumpSetup(
      WidgetTester tester, {
      String displayName = '',
      AccountCompletionDraft account = const AccountCompletionDraft(),
      VoidCallback? onComplete,
    }) async {
      var draft = ProfileSetupDraft(displayName: displayName);
      await pumpTestScreen(
        tester,
        StatefulBuilder(
          builder: (context, setState) => setupScreen(
            draft: draft,
            onChanged: (updatedDraft) => setState(() => draft = updatedDraft),
            account: account,
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

    testWidgets('a space or a mark does not go into the name; a name too '
        'short only turns 다음 off', (tester) async {
      final draft = await pumpSetup(tester);
      final next = find.byKey(
        const ValueKey<String>('profile-setup-next-button'),
      );
      Future<void> type(String name) async {
        await tester.enterText(find.byType(TextFormField), name);
        await tester.pump();
      }

      bool canGoOn() =>
          tester.widget<OnboardingPrimaryButton>(next).onPressed != null;

      // A name too short turns 다음 off and says nothing.
      await type('민');
      expect(find.text('2자 이상으로 입력해 주세요.'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('profile-setup-nickname-feedback')),
        findsNothing,
      );
      expect(canGoOn(), isFalse);

      await type('민지!');
      expect(draft().displayName, '민지');
      expect(find.text('한글, 영문, 숫자만 사용할 수 있어요.'), findsNothing);
      expect(find.text('2/12자'), findsOneWidget);
      expect(canGoOn(), isTrue);

      await type('민 지 2');
      expect(draft().displayName, '민지2');
      expect(find.text('띄어쓰기 없이 입력해 주세요.'), findsNothing);
      expect(canGoOn(), isTrue);

      await type('민지');
      expect(
        find.byKey(const ValueKey<String>('profile-setup-nickname-feedback')),
        findsNothing,
      );
      expect(canGoOn(), isTrue);
    });

    testWidgets('the 천지인 keyboard\'s marks on the way to a vowel are kept, '
        'so the syllable can form', (tester) async {
      final draft = await pumpSetup(tester);

      // ㅅ, then ㆍ and ㅣ make 서.
      for (final typed in <String>[
        'ㅅㆍ',
        'ㅇᆢ',
        'ㅅ\u119E',
        'ㅅ\u00B7',
        'ㅇ\u2025',
      ]) {
        await tester.enterText(find.byType(TextFormField), typed);
        await tester.pump();
        expect(draft().displayName, typed);
        // Still being typed: nothing is said about it.
        expect(
          find.byKey(const ValueKey<String>('profile-setup-nickname-feedback')),
          findsNothing,
        );
      }

      // 완료 on the keyboard over a name a dot was left in says why, and
      // the next key takes the line away.
      await tester.enterText(find.byType(TextFormField), '서ㆍ연');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('한글, 영문, 숫자만 사용할 수 있어요.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '서연');
      await tester.pump();
      expect(draft().displayName, '서연');
      expect(
        find.byKey(const ValueKey<String>('profile-setup-nickname-feedback')),
        findsNothing,
      );
    });

    testWidgets('drink-interest tiles update the draft', (tester) async {
      // A page that already has the birth date and gender shows the tiles.
      final draft = await pumpSetup(
        tester,
        displayName: '민지',
        account: AccountCompletionDraft(
          birthYear: AccountCompletionDraft.latestEligibleBirthYear(),
          birthMonth: 1,
          birthDay: 1,
          gender: ProfileGender.female,
        ),
      );
      await showNextSetupStep(tester);

      await tester.tap(find.text('와인'));
      await tester.pump();

      expect(draft().interestedDrinkTypes, contains(DrinkType.wine));
      expect(find.byType(OnboardingDrinkTile), findsNWidgets(4));
      expect(find.text('사케'), findsOneWidget);
      for (final absent in ['쇼추', '리큐르', '중국술', '맥주', '칵테일']) {
        expect(find.text(absent), findsNothing);
      }
    });
  });
}
