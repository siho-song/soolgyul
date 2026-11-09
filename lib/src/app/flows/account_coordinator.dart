import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/auth/data/social_auth_service.dart';
import '../../features/profile/data/account_completion_draft.dart';
import '../../features/profile/data/account_completion_gateway.dart';
import '../../features/profile/data/drink_interest_catalog.dart';
import '../../features/profile/data/profile_summary_store.dart';
import '../../features/profile/presentation/account_restore_dialog.dart';
import '../../features/profile/data/profile_setup_draft.dart';
import '../../navigation/app_route.dart';
import 'app_gateways.dart';
import 'claim_coordinator.dart';
import 'flow_host.dart';
import 'onboarding_coordinator.dart';
import 'record_coordinator.dart';
import 'taste_card_coordinator.dart';

/// Session and profile ownership: social login, the post-login
/// continuation, sign out, account deletion and My Page preferences.
class AccountCoordinator {
  AccountCoordinator(
    this._host,
    this._gateways,
    this._onboarding,
    this._record,
    this._tasteCard,
    this._claim,
    this._summary,
  );

  final FlowHost _host;
  final AppGateways _gateways;
  final OnboardingCoordinator _onboarding;
  final RecordCoordinator _record;
  final TasteCardCoordinator _tasteCard;
  final ClaimCoordinator _claim;
  final ProfileSummaryStore _summary;

  String nickname = '민지';
  Set<DrinkInterest> interests = Set<DrinkInterest>.of(
    initialProfileDrinkInterests,
  );
  bool profileSetupSaving = false;

  StreamSubscription<SocialAuthSessionEvent>? _sessionSubscription;
  Future<void> _sessionEventHandling = Future<void>.value();
  int _hydrationRequest = 0;
  int _mutationRevision = 0;
  String? _completionIdempotencyKey;
  bool _continuationInProgress = false;
  bool _continuationCompleted = false;
  Timer? _appEntryFallback;

  /// The app entry routes; the web never shows them.
  static const _appEntryRoutes = <AppRoute>{
    AppRoute.appLoading,
    AppRoute.appLogin,
  };

  void listenToSession() {
    _sessionSubscription = _gateways.socialAuth?.sessionEvents.listen(
      _handleSessionEvent,
    );
  }

  /// Leaves the loading screen once the saved session is known. Without an
  /// auth gateway, or when no answer arrives, login opens.
  void startAppEntry() {
    if (_gateways.socialAuth == null) {
      scheduleMicrotask(() => _leaveLoadingFor(AppRoute.appLogin));
      return;
    }
    _appEntryFallback = Timer(
      const Duration(seconds: 3),
      () => _leaveLoadingFor(AppRoute.appLogin),
    );
  }

  void _leaveLoadingFor(AppRoute route) {
    _appEntryFallback?.cancel();
    if (!_host.mounted) return;
    if (_host.router.currentRoute != AppRoute.appLoading) return;
    _host.router.replaceRoot(route);
  }

  void dispose() {
    _appEntryFallback?.cancel();
    unawaited(_sessionSubscription?.cancel());
  }

  void _handleSessionEvent(SocialAuthSessionEvent event) {
    if (!_host.mounted) return;
    _sessionEventHandling = _sessionEventHandling.then(
      (_) => _processSessionEvent(event),
      onError: (_, _) => _processSessionEvent(event),
    );
  }

  Future<void> _processSessionEvent(SocialAuthSessionEvent event) async {
    if (!_host.mounted) return;
    if (_appEntryRoutes.contains(_host.router.currentRoute)) {
      _appEntryFallback?.cancel();
      if (event == SocialAuthSessionEvent.noSession) {
        _leaveLoadingFor(AppRoute.appLogin);
      } else {
        await _enterSignedInApp();
      }
      return;
    }
    if (event == SocialAuthSessionEvent.noSession) return;
    if (!await _resolvePendingDeletion()) return;
    await hydrateProfilePreferences();
  }

  /// Social login from the app's login screen; the signed-in user goes on
  /// to profile setup, the first record or home.
  Future<void> signIn(SocialAuthProvider provider) async {
    final authGateway = _gateways.socialAuth;
    if (authGateway == null) throw SocialAuthException(provider);
    _continuationCompleted = false;
    final result = await authGateway.signIn(provider);
    if (_host.mounted && result == SocialAuthResult.authenticated) {
      await _enterSignedInApp();
    }
  }

  Future<void> signOut() async {
    final authGateway = _gateways.socialAuth;
    if (authGateway == null) {
      throw StateError('로그아웃에 필요한 인증 연결이 없습니다.');
    }
    await authGateway.signOut();
    if (!_host.mounted) return;
    _hydrationRequest++;
    _mutationRevision++;
    nickname = '';
    interests = <DrinkInterest>{};
    _completionIdempotencyKey = null;
    _tasteCard.reset();
    _onboarding.resetAfterSignOut();
    _record.resetAfterSignOut();
    _claim.resetAfterSignOut();
    _summary.clear();
    _continuationCompleted = false;
    _continuationInProgress = false;
    _host.router.replaceRoot(
      _gateways.isWeb ? AppRoute.onboardingWelcome : AppRoute.appLogin,
    );
  }

  /// App entry with a session: a finished account lands on home, an
  /// unfinished one continues with profile setup. Runs once per sign-in.
  Future<void> _enterSignedInApp() async {
    if (_continuationInProgress || _continuationCompleted) return;
    _continuationInProgress = true;
    try {
      if (!await _resolvePendingDeletion()) {
        _leaveLoadingFor(AppRoute.appLogin);
        return;
      }
      AccountCompletionStatus? accountStatus;
      final accountGateway = _gateways.accountCompletion;
      if (accountGateway != null) {
        try {
          accountStatus = await accountGateway.fetchStatus();
        } catch (_) {
          if (!_host.mounted) return;
          _host.showFeedback('가입 상태를 확인하지 못했어요. 잠시 후 다시 시도해주세요.');
          _leaveLoadingFor(AppRoute.appLogin);
          return;
        }
      }
      if (!_host.mounted) return;
      if (accountStatus?.deletionState == 'scheduled') {
        _continuationCompleted = true;
        _host.showFeedback('탈퇴 대기 중인 계정이에요. 계정 복구 후 다시 시도해주세요.');
        _leaveLoadingFor(AppRoute.appLogin);
        return;
      }
      if (accountStatus == null || accountStatus.isReady) {
        // A failed profile fetch already told the user; the app still opens.
        await hydrateProfilePreferences();
        if (!_host.mounted) return;
        _continuationCompleted = true;
        await _landSignedIn();
        return;
      }
      await hydrateProfilePreferences(prefillProfileSetup: true);
      if (!_host.mounted) return;
      _continuationCompleted = true;
      // Back from profile setup returns to the login screen.
      _host.router
        ..replaceRoot(AppRoute.appLogin)
        ..push(AppRoute.profileSetup);
    } finally {
      _continuationInProgress = false;
    }
  }

  Future<void> requestAccountDeletion() async {
    await _gateways.accountDeletion!.requestDeletion();
    await signOut();
  }

  /// Lands on the first-record onboarding or home after profile setup.
  Future<void> _finishSignedInEntry() async {
    if (!_host.mounted) return;
    await _landSignedIn();
  }

  /// A web card waiting to be claimed is claimed first and shown over
  /// home; otherwise the account lands on the first record or home.
  Future<void> _landSignedIn() async {
    if (await _claim.claimPending()) {
      if (!_host.mounted) return;
      _host.router
        ..replaceRoot(AppRoute.home)
        ..push(AppRoute.onboardingResult);
      return;
    }
    final landing = await _signedInLanding();
    if (!_host.mounted) return;
    _host.router.replaceRoot(landing);
  }

  /// An account without a saved card starts with the first record; one
  /// with a card opens home. The counts stay for My Page.
  Future<AppRoute> _signedInLanding() async {
    try {
      final summary = await _summary.load();
      return summary?.cardCount == 0
          ? AppRoute.onboardingWelcome
          : AppRoute.home;
    } catch (_) {
      return AppRoute.home;
    }
  }

  Future<bool> _resolvePendingDeletion() async {
    final gateway = _gateways.accountDeletion;
    if (gateway == null) return true;
    try {
      final status = await gateway.fetchStatus();
      final context = _host.context;
      if (!_host.mounted || !context.mounted) return false;
      if (status.state == 'active') return true;
      final restored = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AccountRestoreDialog(gateway: gateway, status: status),
      );
      if (restored == true) {
        await hydrateProfilePreferences();
        if (_host.mounted) _host.router.replaceRoot(AppRoute.home);
        return false;
      }
      await signOut();
      return false;
    } catch (_) {
      if (_host.mounted) {
        _host.showFeedback('계정 상태를 확인하지 못했어요. 다시 로그인해주세요.');
      }
      return false;
    }
  }

  Future<bool> hydrateProfilePreferences({
    bool prefillProfileSetup = false,
  }) async {
    final profileGateway = _gateways.profilePreferences;
    if (profileGateway == null) return true;

    final hydrationRequest = ++_hydrationRequest;
    final mutationRevision = _mutationRevision;
    try {
      final preferences = await profileGateway.fetchProfilePreferences();
      if (!_host.mounted ||
          hydrationRequest != _hydrationRequest ||
          mutationRevision != _mutationRevision) {
        return false;
      }
      _host.refresh(() {
        final displayName = preferences.displayName?.trim();
        if (displayName != null && displayName.isNotEmpty) {
          nickname = displayName;
        }
        interests = Set<DrinkInterest>.of(preferences.interests);
        if (prefillProfileSetup) {
          _onboarding.state.updateProfile(
            ProfileSetupDraft(
              displayName: displayName ?? '',
              interestedDrinkTypes: preferences.interests,
            ),
          );
        }
      });
      return true;
    } catch (_) {
      if (_host.mounted && hydrationRequest == _hydrationRequest) {
        _host.showFeedback('프로필 정보를 불러오지 못했어요. 잠시 후 다시 시도해주세요.');
      }
      return false;
    }
  }

  void updateProfileSetup(ProfileSetupDraft updatedDraft) {
    _host.refresh(() {
      _completionIdempotencyKey = null;
      _onboarding.state.updateProfile(updatedDraft);
    });
  }

  void updateAccountCompletion(AccountCompletionDraft updatedDraft) {
    _host.refresh(() {
      _completionIdempotencyKey = null;
      _onboarding.state.updateAccountCompletion(updatedDraft);
    });
  }

  /// Saves the post-login name, interests and legal confirmation together.
  Future<void> completeProfileSetup() async {
    final profileDraft = _onboarding.state.profileSetupDraft;
    final accountDraft = _onboarding.state.accountCompletionDraft;
    final profileGateway = _gateways.profilePreferences;
    if (profileSetupSaving ||
        !profileDraft.hasValidDisplayName ||
        !profileDraft.hasValidDrinkInterests ||
        !accountDraft.canComplete) {
      return;
    }
    _host.refresh(() => profileSetupSaving = true);
    try {
      var savedDisplayName = profileDraft.displayName;
      final accountGateway = _gateways.accountCompletion;
      final savedInterests = profileGateway == null
          ? profileDraft.interestedDrinkTypes
          : await profileGateway.replaceDrinkInterests(
              profileDraft.interestedDrinkTypes,
            );
      if (accountGateway != null) {
        _completionIdempotencyKey ??= createAccountCompletionUuidV4();
        final status = await accountGateway.complete(
          CompleteAccountRequest.fromDraft(
            idempotencyKey: _completionIdempotencyKey!,
            displayName: profileDraft.displayName,
            draft: accountDraft,
          ),
        );
        savedDisplayName = status.displayName ?? profileDraft.displayName;
      } else if (profileGateway != null) {
        savedDisplayName = await profileGateway.updateDisplayName(
          profileDraft.displayName,
        );
      }
      if (!_host.mounted) return;
      _host.refresh(() {
        _completionIdempotencyKey = null;
        _mutationRevision += 1;
        nickname = savedDisplayName;
        interests = Set<DrinkInterest>.of(savedInterests);
      });
      await _finishSignedInEntry();
    } catch (_) {
      if (_host.mounted) {
        _host.showFeedback('프로필 설정을 저장하지 못했어요. 잠시 후 다시 시도해주세요.');
      }
    } finally {
      if (_host.mounted) {
        _host.refresh(() => profileSetupSaving = false);
      } else {
        profileSetupSaving = false;
      }
    }
  }

  /// Saves the nickname from the My Page sheet; the sheet closes on true
  /// and shows the failure itself on false.
  Future<bool> saveNickname(String updated) async {
    final profileGateway = _gateways.profilePreferences;
    if (profileGateway == null) {
      _host.refresh(() {
        _mutationRevision += 1;
        nickname = updated;
      });
      return true;
    }
    try {
      final savedDisplayName = await profileGateway.updateDisplayName(updated);
      if (!_host.mounted) return false;
      _host.refresh(() {
        _mutationRevision += 1;
        nickname = savedDisplayName;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stores the drink interests from the My Page sheet; the sheet stays
  /// open and says so when this returns false.
  Future<bool> saveProfileInterests(Set<DrinkInterest> updated) async {
    final profileGateway = _gateways.profilePreferences;
    if (profileGateway == null) {
      _host.refresh(() {
        _mutationRevision += 1;
        interests = Set<DrinkInterest>.of(updated);
      });
      return true;
    }
    try {
      final savedInterests = await profileGateway.replaceDrinkInterests(
        updated,
      );
      if (!_host.mounted) return false;
      _host.refresh(() {
        _mutationRevision += 1;
        interests = Set<DrinkInterest>.of(savedInterests);
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
