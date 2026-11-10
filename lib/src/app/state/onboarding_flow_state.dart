import '../../features/onboarding/data/onboarding_entry_draft.dart';
import '../../features/profile/data/profile_setup_draft.dart';
import '../../features/profile/data/account_completion_draft.dart';
import 'sensory_session.dart';

class OnboardingFlowState {
  OnboardingFlowState.initial()
    : entryDraft = const OnboardingEntryDraft.fromFeelingOnly(),
      profileSetupDraft = ProfileSetupDraft(displayName: ''),
      accountCompletionDraft = const AccountCompletionDraft();

  OnboardingEntryDraft entryDraft;
  ProfileSetupDraft profileSetupDraft;
  AccountCompletionDraft accountCompletionDraft;
  final SensorySession sensory = SensorySession();

  void resetEntry() {
    sensory.clear();
    entryDraft = const OnboardingEntryDraft.fromFeelingOnly();
    profileSetupDraft = ProfileSetupDraft(displayName: '');
    accountCompletionDraft = const AccountCompletionDraft();
  }

  /// Keeps profile data; clears product-dependent input.
  void startWith(OnboardingEntryDraft nextEntryDraft) {
    sensory.clear();
    entryDraft = nextEntryDraft;
  }

  void updateProfile(ProfileSetupDraft updatedDraft) {
    profileSetupDraft = updatedDraft;
  }

  void updateAccountCompletion(AccountCompletionDraft updatedDraft) {
    accountCompletionDraft = updatedDraft;
  }
}
