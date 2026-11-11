import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/app_sheet.dart';

import '../../features/auth/data/social_auth_service.dart';
import '../../features/catalog/data/suggested_drinks.dart';
import '../../features/profile/data/account_completion_draft.dart';
import '../../features/profile/data/account_completion_gateway.dart';
import '../../features/profile/data/drink_interest_catalog.dart';
import '../../features/profile/data/profile_summary_provider.dart';
import '../../features/profile/presentation/account_deleting_sheet.dart';
import '../../features/profile/data/profile_setup_draft.dart';
import '../../navigation/app_route.dart';
import 'app_gateways.dart';
import 'claim_coordinator.dart';
import 'flow_host.dart';
import 'onboarding_coordinator.dart';
import 'record_coordinator.dart';
import 'taste_card_coordinator.dart';
import '../../core/ids.dart';
import '../../core/kept_first.dart';
import '../../features/profile/data/profile_preferences_gateway.dart';
import '../../core/errors/error_report.dart';

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
    this._summary, {
    required this.onSignedOut,
    required this.onLanded,
  });

  final FlowHost _host;
  final AppGateways _gateways;
  final OnboardingCoordinator _onboarding;
  final RecordCoordinator _record;
  final TasteCardCoordinator _tasteCard;
  final ClaimCoordinator _claim;
  final ProfileSummaryNotifier _summary;

  /// Forgets what the app holds of the account that signed out.
  final VoidCallback onSignedOut;

  /// The signed-in account has just landed on home.
  final VoidCallback onLanded;

  String nickname = '민지';
  Set<DrinkInterest> interests = Set<DrinkInterest>.of(
    initialProfileDrinkInterests,
  );

  /// The member's gender, which picks the 자주 찾는 술 list; `null` for a
  /// guest or before the profile is read.
  ProfileGender? gender;
  bool profileSetupSaving = false;

  StreamSubscription<SocialAuthSessionEvent>? _sessionSubscription;
  Future<void> _sessionEventHandling = Future<void>.value();
  int _hydrationRequest = 0;
  int _mutationRevision = 0;
  String? _completionIdempotencyKey;

  /// The app itself asked for the sign-out that is about to be announced.
  bool _signOutAsked = false;

  /// A withdrawal is being asked for; the end of session that comes with it
  /// is the member's own doing.
  bool _withdrawing = false;
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
      onError: _handleSessionError,
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

  /// The auth client could not do something on its own: renew the sign-in
  /// while offline (ordinary, and tried again by the client), or finish a
  /// login that came back from the provider's page. The second is said, so
  /// the login screen is not left without a word.
  void _handleSessionError(Object error, StackTrace stack) {
    reportError(error, stack, where: 'session');
    if (!_host.mounted || !worthReporting(error)) return;
    if (!_appEntryRoutes.contains(_host.router.currentRoute)) return;
    _host.showFeedback('로그인을 완료하지 못했어요. 다시 시도해 주세요.');
    _leaveLoadingFor(AppRoute.appLogin);
  }

  void _handleSessionEvent(SocialAuthSessionEvent event) {
    if (!_host.mounted) return;
    // The end of a session waits for nothing that is still being asked.
    if (event == SocialAuthSessionEvent.signedOut) {
      _leaveAccount();
      return;
    }
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
    if (await _resolvePendingDeletion() == _DeletionCheck.stopped) return;
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
      _gateways.analytics.event('login', <String, Object>{
        'method': provider.name,
      });
      await _enterSignedInApp();
    }
  }

  /// Asks for the sign-out. What follows it happens in [_leaveAccount], when
  /// the session's end is announced.
  Future<void> signOut() async {
    final authGateway = _gateways.socialAuth;
    if (authGateway == null) {
      throw StateError('no auth gateway to sign out with');
    }
    _signOutAsked = true;
    try {
      // While the session can still ask the server to.
      if (!_gateways.isWeb) await _gateways.notifications?.forgetThisPhone();
      await authGateway.signOut();
    } finally {
      _signOutAsked = false;
    }
  }

  /// The session ended: nothing of the account stays in the app or on the
  /// phone, and the entry screen opens. A member who did not ask for it (the
  /// server refused to renew the sign-in, or another tab signed out) is told.
  void _leaveAccount() {
    final withdrew = _withdrawing;
    final asked = _signOutAsked || withdrew;
    _signOutAsked = false;
    _withdrawing = false;
    _hydrationRequest++;
    _mutationRevision++;
    nickname = '';
    interests = <DrinkInterest>{};
    gender = null;
    _completionIdempotencyKey = null;
    _tasteCard.reset();
    _onboarding.resetAfterSignOut();
    _record.resetAfterSignOut();
    _claim.resetAfterSignOut();
    onSignedOut();
    _continuationCompleted = false;
    _continuationInProgress = false;
    _appEntryFallback?.cancel();
    if (withdrew) {
      _host.showFeedback('탈퇴가 접수됐어요. 30일 이내에 다시 로그인하면 복구돼요.', success: true);
    } else if (!asked) {
      _host.showFeedback('로그아웃됐어요. 다시 로그인해 주세요.');
    }
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
      if (await _enterFromPhone()) return;
      // The sign-up state is asked while the deletion state is checked.
      final accountGateway = _gateways.accountCompletion;
      var statusRequest = accountGateway?.fetchStatus();
      statusRequest?.ignore();
      final deletion = await _resolvePendingDeletion();
      if (deletion == _DeletionCheck.stopped) {
        _leaveLoadingFor(AppRoute.appLogin);
        return;
      }
      // What was asked before a restore still describes the waiting account.
      if (deletion == _DeletionCheck.restored) {
        statusRequest = accountGateway?.fetchStatus();
      }
      AccountCompletionStatus? accountStatus;
      if (statusRequest != null) {
        try {
          accountStatus = await statusRequest;
        } catch (_) {
          if (!_host.mounted) return;
          _host.showFeedback('가입 상태를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
          _leaveLoadingFor(AppRoute.appLogin);
          return;
        }
      }
      if (!_host.mounted) return;
      if (accountStatus?.deletionState == 'scheduled') {
        _continuationCompleted = true;
        _host.showFeedback('탈퇴 대기 중인 계정이에요. 계정 복구 후 다시 시도해 주세요.');
        _leaveLoadingFor(AppRoute.appLogin);
        return;
      }
      if (accountStatus == null || accountStatus.isReady) {
        _continuationCompleted = true;
        // The next launch may open home before the account is asked about.
        unawaited(
          _gateways.savedViews?.write(_enteredName, <String, Object?>{
            'ready': true,
          }),
        );
        // The profile loads while the landing is worked out. A failed
        // profile fetch already told the user; the app still opens.
        await _landSignedIn(alongside: hydrateProfilePreferences());
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

  /// The mark the phone keeps once an account has entered as ready.
  static const _enteredName = 'entered';

  /// Opens home at once for a member the phone remembers: the profile and
  /// the screens come from what it kept, and the account is checked behind
  /// home instead of in front of it. False when the phone keeps nothing of
  /// this account (a first sign-in, a new phone, after a sign-out) or a web
  /// card is waiting to be claimed; the entry then asks first, as before.
  Future<bool> _enterFromPhone() async {
    final saved = _gateways.savedViews;
    final keeper = switch (_gateways.profilePreferences) {
      final KeepsLast<ProfilePreferences> keeper => keeper,
      _ => null,
    };
    if (saved == null || keeper == null || _claim.hasPending) return false;
    final entered = await saved.read(_enteredName);
    final kept = await keeper.kept();
    final name = kept?.displayName?.trim() ?? '';
    if (!_host.mounted) return true;
    if (entered is! Map || entered['ready'] != true) return false;
    if (kept == null || name.isEmpty) return false;
    _host.refresh(() {
      nickname = name;
      interests = Set<DrinkInterest>.of(kept.interests);
      gender = kept.gender;
    });
    _continuationCompleted = true;
    _summary.refresh();
    _host.router.replaceRoot(AppRoute.home);
    onLanded();
    unawaited(_confirmAccountBehindHome());
    return true;
  }

  /// What [_enterFromPhone] skipped: since the phone's copy was kept, the
  /// account may have been set to be deleted, or may need its profile again.
  /// A server that cannot be reached or fails changes nothing; the member
  /// keeps reading what the phone kept. A sign-in that is no longer valid is
  /// not found here: its end is announced, and [_leaveAccount] hears it.
  Future<void> _confirmAccountBehindHome() async {
    final accountGateway = _gateways.accountCompletion;
    var statusRequest = accountGateway?.fetchStatus();
    statusRequest?.ignore();
    final deletion = await _resolvePendingDeletion(tellFailure: false);
    if (deletion == _DeletionCheck.stopped ||
        deletion == _DeletionCheck.unreachable) {
      return;
    }
    if (deletion == _DeletionCheck.restored) {
      statusRequest = accountGateway?.fetchStatus();
    }
    AccountCompletionStatus? accountStatus;
    try {
      accountStatus = await statusRequest;
    } catch (_) {
      return;
    }
    // The member may have left while the account was being asked about.
    if (!_host.mounted || !_continuationCompleted) return;
    if (accountStatus?.deletionState == 'scheduled') {
      unawaited(_gateways.savedViews?.remove(_enteredName));
      _host.showFeedback('탈퇴 대기 중인 계정이에요. 계정 복구 후 다시 시도해 주세요.');
      _host.router.replaceRoot(AppRoute.appLogin);
      return;
    }
    if (accountStatus != null && !accountStatus.isReady) {
      unawaited(_gateways.savedViews?.remove(_enteredName));
      await hydrateProfilePreferences(
        prefillProfileSetup: true,
        tellFailure: false,
      );
      if (!_host.mounted) return;
      _host.router
        ..replaceRoot(AppRoute.appLogin)
        ..push(AppRoute.profileSetup);
      return;
    }
    await hydrateProfilePreferences(tellFailure: false);
  }

  /// Schedules the withdrawal and leaves the account. Once the server has
  /// scheduled it, the account is left whatever becomes of the sign-out.
  Future<void> requestAccountDeletion() async {
    _withdrawing = true;
    try {
      await _gateways.accountDeletion!.requestDeletion();
      try {
        await signOut();
      } catch (_) {
        // The server ended every session when it scheduled the withdrawal.
      }
      // No end of session was announced: leave all the same.
      if (_withdrawing && _host.mounted) _leaveAccount();
    } finally {
      _withdrawing = false;
    }
  }

  /// Lands on home after profile setup.
  Future<void> _finishSignedInEntry() async {
    if (!_host.mounted) return;
    await _landSignedIn();
  }

  /// A web card waiting to be claimed is claimed first and shown over
  /// home; otherwise the account lands on home, with or without a card. The
  /// landing page opens once [alongside] has finished too.
  Future<void> _landSignedIn({Future<void>? alongside}) async {
    if (await _claim.claimPending()) {
      await alongside;
      if (!_host.mounted) return;
      _host.router
        ..replaceRoot(AppRoute.home)
        ..push(AppRoute.onboardingResult);
      onLanded();
      return;
    }
    // The counts tell 기록하기 whether this is the first record, and stay
    // for My Page.
    _summary.refresh();
    await alongside;
    if (!_host.mounted) return;
    _host.router.replaceRoot(AppRoute.home);
    onLanded();
  }

  /// [tellFailure] false is the check behind home: a failed check answers
  /// [_DeletionCheck.unreachable] and nobody is told.
  Future<_DeletionCheck> _resolvePendingDeletion({
    bool tellFailure = true,
  }) async {
    final gateway = _gateways.accountDeletion;
    if (gateway == null) return _DeletionCheck.active;
    try {
      final status = await gateway.fetchStatus();
      if (!_host.mounted) return _DeletionCheck.stopped;
      if (status.state == 'active') return _DeletionCheck.active;
      // Signing in again within the 30 days is the restore: the account
      // goes on like any signed-in one, and is only told so.
      if (status.canRestore) {
        await gateway.restore();
        if (!_host.mounted) return _DeletionCheck.stopped;
        _host.showFeedback('탈퇴가 취소되고 계정이 복구됐어요.', success: true);
        return _DeletionCheck.restored;
      }
      // The host's own context sits above the Navigator; a sheet needs
      // one from inside it.
      final context = _host.router.navigatorKey.currentContext;
      if (context == null || !context.mounted) return _DeletionCheck.stopped;
      await showAppSheet<void>(
        context: context,
        dismissible: false,
        builder: (_) => const AccountDeletingSheet(),
      );
      await signOut();
      return _DeletionCheck.stopped;
    } catch (_) {
      if (!tellFailure) return _DeletionCheck.unreachable;
      if (_host.mounted) {
        _host.showFeedback('계정 상태를 확인하지 못했어요. 다시 로그인해 주세요.');
      }
      return _DeletionCheck.stopped;
    }
  }

  Future<bool> hydrateProfilePreferences({
    bool prefillProfileSetup = false,
    bool tellFailure = true,
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
        gender = preferences.gender;
        if (prefillProfileSetup) {
          _onboarding.state.updateProfile(
            ProfileSetupDraft(
              displayName: displayName ?? '',
              interestedDrinkTypes: preferences.interests,
            ),
          );
        }
      });
      // The member's 자주 찾는 술 are looked up now, so a search page shows
      // them the moment it opens.
      final catalogSearch = _gateways.catalogSearch;
      if (catalogSearch != null) {
        unawaited(
          SuggestedDrinks.load(catalogSearch, suggestedDrinkNamesFor(gender)),
        );
      }
      return true;
    } catch (_) {
      if (tellFailure &&
          _host.mounted &&
          hydrationRequest == _hydrationRequest) {
        _host.showFeedback('프로필 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
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
        _completionIdempotencyKey ??= createUuidV4();
        final status = await accountGateway.complete(
          CompleteAccountRequest.fromDraft(
            idempotencyKey: _completionIdempotencyKey!,
            displayName: profileDraft.displayName,
            draft: accountDraft,
          ),
        );
        savedDisplayName = status.displayName ?? profileDraft.displayName;
        _gateways.analytics.event('sign_up');
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
        gender = accountDraft.gender;
      });
      await _finishSignedInEntry();
    } catch (_) {
      if (_host.mounted) {
        _host.showFeedback('프로필 설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
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

/// What the check for a pending account deletion found.
enum _DeletionCheck {
  /// No deletion is waiting.
  active,

  /// One was waiting and the member took the account back.
  restored,

  /// The entry ends here: the member left, or the state is unknown.
  stopped,

  /// The check failed behind home, and nobody was told.
  unreachable,
}
