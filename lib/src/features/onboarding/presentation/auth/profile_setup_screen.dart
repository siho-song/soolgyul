import 'dart:async';

import '../../../../widgets/app_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../design/app_layout.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_sheet.dart';
import '../../../../widgets/app_text_field.dart';
import '../../../../widgets/kept_text.dart';
import '../../../profile/data/account_completion_draft.dart';
import '../../../profile/data/drink_interest_catalog.dart';
import '../../../profile/data/nickname_rule.dart';
import '../../../profile/data/profile_setup_draft.dart';
import '../widgets/onboarding_actions.dart';
import '../widgets/onboarding_buttons.dart';
import 'birth_date_picker.dart';
import '../../../../widgets/failure_words.dart';

/// What the setup page asks, in the order it asks.
enum _SetupStep { nickname, basicInfo, interests }

/// What the agreements sheet draws: the checks, whether a save is running
/// and whether the last one failed.
typedef _AgreementsShown = ({
  AccountCompletionDraft account,
  bool submitting,
  bool saveFailed,
  Object? saveError,
});

/// One agreement row's change, applied to the draft as it is when pressed.
typedef _AgreementChange =
    AccountCompletionDraft Function(AccountCompletionDraft draft);

/// The post-login setup page. It asks one thing at a time: the nickname
/// first, then birth date and gender, then drink interests. The one being
/// asked sits right under the question; the ones already answered move
/// down under it, the newest first, and can still be changed. After the
/// last, 다음 opens the agreements in a sheet, whose start button saves
/// everything together. A save that fails leaves the sheet open, saying so
/// over the button, which takes another press.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    required this.profileDraft,
    required this.onProfileChanged,
    required this.accountDraft,
    required this.onAccountChanged,
    required this.onComplete,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
    this.submitting = false,
    this.saveError,
    super.key,
  });

  final ProfileSetupDraft profileDraft;
  final ValueChanged<ProfileSetupDraft> onProfileChanged;
  final AccountCompletionDraft accountDraft;
  final ValueChanged<AccountCompletionDraft> onAccountChanged;
  final VoidCallback onComplete;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;
  final bool submitting;

  /// What the last save failed with, when the flow knows: a connection
  /// failure is then told as one.
  final Object? saveError;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final FocusNode _nicknameFocus = FocusNode();
  final ScrollController _answers = ScrollController();

  /// The step being asked, at the top of the page; the ones before it are
  /// under it.
  late _SetupStep _asked = _stepAtOpen();

  /// Steps shown from the start are simply there; later ones fade in.
  late final _SetupStep _askedAtOpen = _asked;

  /// The agreements sheet is a route of its own, which this page's rebuild
  /// does not reach: it draws what this holds.
  late final ValueNotifier<_AgreementsShown> _agreementsShown =
      ValueNotifier<_AgreementsShown>(_agreementsNow);
  bool _agreementsOpen = false;

  /// The sheet's start button was pressed and its save is not over.
  bool _saveAsked = false;

  /// The last save did not go through, and nothing was changed since.
  bool _saveFailed = false;

  _AgreementsShown get _agreementsNow => (
    account: accountDraft,
    submitting: submitting,
    saveFailed: _saveFailed,
    saveError: widget.saveError,
  );

  ProfileSetupDraft get profileDraft => widget.profileDraft;
  ValueChanged<ProfileSetupDraft> get onProfileChanged =>
      widget.onProfileChanged;
  AccountCompletionDraft get accountDraft => widget.accountDraft;
  ValueChanged<AccountCompletionDraft> get onAccountChanged =>
      widget.onAccountChanged;
  bool get submitting => widget.submitting;

  /// A page opened with answers already in its drafts starts where they
  /// stop: at the furthest step started, or at one before it that is still
  /// unanswered.
  _SetupStep _stepAtOpen() {
    final started = profileDraft.interestedDrinkTypes.isNotEmpty
        ? _SetupStep.interests
        : accountDraft.birthYear != null || accountDraft.gender != null
        ? _SetupStep.basicInfo
        : _SetupStep.nickname;
    return _SetupStep.values.firstWhere(
      (step) => step == started || !_answered(step),
    );
  }

  static bool _basicInfoAnswered(AccountCompletionDraft account) =>
      account.hasEligibleBirthYear &&
      account.birthDate != null &&
      account.hasGender;

  bool _answered(_SetupStep step) => switch (step) {
    _SetupStep.nickname => profileDraft.hasValidDisplayName,
    _SetupStep.basicInfo => _basicInfoAnswered(accountDraft),
    _SetupStep.interests => profileDraft.hasValidDrinkInterests,
  };

  /// Whether every step on screen is answered, so the next may show.
  bool get _shownAnswered =>
      _SetupStep.values.take(_asked.index + 1).every(_answered);

  String get _question => switch (_asked) {
    _SetupStep.nickname => '닉네임을 알려 주세요',
    _SetupStep.basicInfo => '생년월일과 성별을 알려 주세요',
    _SetupStep.interests => '관심 있는 주종을 골라 주세요',
  };

  @override
  void didUpdateWidget(covariant ProfileSetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Both pickers answered leaves nothing to press on that step.
    if (_asked == _SetupStep.basicInfo &&
        !_basicInfoAnswered(oldWidget.accountDraft) &&
        _shownAnswered) {
      _asked = _SetupStep.interests;
      _scrollToAsked();
    }
    // A save that was asked for and is over with this page still here did
    // not go through. The page's notice of it is under the sheet, so the
    // sheet says it too.
    if (_saveAsked && !submitting) {
      _saveAsked = false;
      _saveFailed = true;
    }
    if (!_agreementsOpen) return;
    // The sheet may not be rebuilt while this page builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _agreementsShown.value = _agreementsNow;
    });
  }

  @override
  void dispose() {
    _agreementsShown.dispose();
    _answers.dispose();
    _nicknameFocus.dispose();
    super.dispose();
  }

  /// 다음: the next step appears on top, and after the last one the
  /// agreements open.
  void _showNext() {
    if (!_shownAnswered) return;
    _nicknameFocus.unfocus();
    if (_asked == _SetupStep.values.last) {
      unawaited(_openAgreements());
      return;
    }
    setState(() => _asked = _SetupStep.values[_asked.index + 1]);
    _scrollToAsked();
    // The birth date is the first thing to answer there: its picker opens
    // without a press, this once.
    if (_asked == _SetupStep.basicInfo && accountDraft.birthDate == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_pickBirthDate());
      });
    }
  }

  /// The sheet's start button. [ProfileSetupScreen.submitting] is true from
  /// this call until the save ends.
  void _start() {
    _saveAsked = true;
    _saveFailed = false;
    widget.onComplete();
  }

  /// The step that appeared is the first on the page: scrolls to its top.
  void _scrollToAsked() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_answers.hasClients) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _answers.jumpTo(0);
      } else {
        _answers.animateTo(
          0,
          duration: AppDurations.slow,
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Opens the agreements over the page. Closed without starting, it leaves
  /// the page as it was and keeps its checks for the next time.
  Future<void> _openAgreements() async {
    if (_agreementsOpen) return;
    _agreementsOpen = true;
    _saveFailed = false;
    _agreementsShown.value = _agreementsNow;
    await showAppSheet<void>(
      context: context,
      builder: (context) => ValueListenableBuilder<_AgreementsShown>(
        valueListenable: _agreementsShown,
        builder: (context, shown, _) => _AgreementsSheet(
          account: shown.account,
          submitting: shown.submitting,
          saveFailed: shown.saveFailed,
          saveError: shown.saveError,
          // From the page's own draft: two rows pressed within one frame
          // both count.
          onChanged: (change) {
            _saveFailed = false;
            onAccountChanged(change(accountDraft));
          },
          onStart: _start,
          onOpenTerms: () => widget.onOpenTerms(),
          onOpenPrivacy: () => widget.onOpenPrivacy(),
        ),
      ),
    );
    _agreementsOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!AppLayout.isViewportReady(constraints)) {
          return const SizedBox.shrink();
        }
        final layout = AppScreenLayout.fromConstraints(constraints);
        final gap = layout.availableContentWidth < 340 ? 8.0 : 10.0;
        final tileWidth = (layout.availableContentWidth - gap) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The question stays above the answers as they scroll.
            Padding(
              padding: EdgeInsets.fromLTRB(
                layout.horizontalPadding,
                AppSpacing.xl,
                layout.horizontalPadding,
                AppSpacing.sm,
              ),
              child: AnimatedSwitcher(
                duration: AppDurations.standard,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topLeft,
                  children: <Widget>[...previous, ?current],
                ),
                child: KeptText(
                  _question,
                  key: ValueKey<_SetupStep>(_asked),
                  style: const AppTextStyle(
                    fontSize: 24,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppFonts.display,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _answers,
                padding: EdgeInsets.fromLTRB(
                  layout.horizontalPadding,
                  AppSpacing.md,
                  layout.horizontalPadding,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // The step being asked first, then the answered ones,
                    // the newest of them on top.
                    for (final step
                        in _SetupStep.values
                            .take(_asked.index + 1)
                            .toList()
                            .reversed)
                      _Appearing(
                        key: ValueKey<_SetupStep>(step),
                        animate: step.index > _askedAtOpen.index,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: step == _SetupStep.nickname
                                ? 0
                                : AppSpacing.xl,
                          ),
                          child: _section(step, gap, tileWidth),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.horizontalPadding,
                  AppSpacing.sm,
                  layout.horizontalPadding,
                  AppSpacing.xl,
                ),
                child: OnboardingPrimaryButton(
                  key: const ValueKey<String>('profile-setup-next-button'),
                  // The sheet may be closed while its save still runs.
                  label: submitting ? '가입하는 중...' : '다음',
                  onPressed: !_shownAnswered || submitting ? null : _showNext,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section(_SetupStep step, double gap, double tileWidth) {
    Widget titled(Widget title, Widget answer) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        title,
        const SizedBox(height: AppSpacing.s10),
        answer,
      ],
    );
    return switch (step) {
      _SetupStep.nickname => titled(_sectionTitle('닉네임'), _nicknameField()),
      _SetupStep.basicInfo => titled(_sectionTitle('기본 정보'), _basicInfoRow()),
      _SetupStep.interests => titled(
        _sectionTitle('관심 주종', hint: '(여러 개 골라도 괜찮아요)'),
        _interestGrid(gap, tileWidth),
      ),
    };
  }

  Widget _sectionTitle(String title, {String? hint}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          title,
          style: const AppTextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: AppSpacing.s6),
          Text(
            hint,
            style: const AppTextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }

  /// Why the typed name cannot be used, in My Page's words; null for an
  /// empty or a usable one. The 천지인 keyboard writes ㆍ and ᆢ on the way to
  /// a vowel: a name holding one is still being typed, and nothing is said.
  String? get _nicknameError {
    final name = profileDraft.displayName;
    if (name.isEmpty || profileDraft.hasValidDisplayName) return null;
    if (name.contains(RegExp(r'\s'))) return '띄어쓰기 없이 입력해 주세요.';
    if (name.contains(nicknameBeingTyped)) return null;
    if (!nicknamePattern.hasMatch(name)) {
      return '한글, 영문, 숫자만 사용할 수 있어요.';
    }
    return name.characters.length < ProfileSetupDraft.minimumDisplayNameLength
        ? '2자 이상으로 입력해 주세요.'
        : '12자 이내로 입력해 주세요.';
  }

  Widget _nicknameField() {
    final length = profileDraft.displayName.characters.length;
    final error = _nicknameError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 54,
          child: Stack(
            children: <Widget>[
              // A space or a mark is not let in. The dots a keyboard
              // composes a vowel through are, and a name left with one is
              // explained under the field.
              AppTextField(
                focusNode: _nicknameFocus,
                inputFormatters: <TextInputFormatter>[nicknameInput],
                // The only thing to do on a fresh page is to type the name.
                autofocus: profileDraft.displayName.isEmpty,
                initialValue: profileDraft.displayName,
                maxLength: ProfileSetupDraft.maximumDisplayNameLength,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (_asked == _SetupStep.nickname) _showNext();
                },
                hintText: '예) 위스키사랑, 밤바다한잔',
                size: AppTextFieldSize.compact,
                enabled: !submitting,
                onChanged: (displayName) => onProfileChanged(
                  profileDraft.copyWith(displayName: displayName),
                ),
              ),
              Positioned(
                right: 14,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Text(
                      '$length/${ProfileSetupDraft.maximumDisplayNameLength}자',
                      style: const AppTextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            error,
            key: const ValueKey<String>('profile-setup-nickname-feedback'),
            style: AppTextStyles.body.copyWith(color: AppColors.actionPrimary),
          ),
        ],
      ],
    );
  }

  Widget _interestGrid(double gap, double tileWidth) {
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: <Widget>[
        for (final option in drinkInterestOptions)
          SizedBox(
            width: tileWidth,
            child: OnboardingDrinkTile(
              icon: option.icon,
              label: option.label,
              emoji: option.emoji,
              horizontal: true,
              selected: profileDraft.interestedDrinkTypes.contains(
                option.value,
              ),
              onPressed: () {
                if (!submitting) {
                  onProfileChanged(
                    profileDraft.toggleDrinkInterest(option.value),
                  );
                }
              },
            ),
          ),
      ],
    );
  }

  Widget _basicInfoRow() {
    final birthDate = accountDraft.birthDate;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 13,
          child: AppPickerField(
            key: const ValueKey<String>('birth-date-field'),
            icon: AppIconAsset.calendar,
            label: birthDate == null
                ? '생년월일 선택'
                : '${birthDate.year}년 ${birthDate.month}월 ${birthDate.day}일',
            filled: birthDate != null,
            onTap: submitting ? null : _pickBirthDate,
          ),
        ),
        const SizedBox(width: AppSpacing.s10),
        Expanded(flex: 7, child: _genderField()),
      ],
    );
  }

  Future<void> _pickBirthDate() async {
    final picked = await showBirthDatePicker(
      context,
      initialDate: accountDraft.birthDate,
    );
    if (picked == null) return;
    onAccountChanged(
      accountDraft.copyWith(
        birthYear: picked.year,
        birthMonth: picked.month,
        birthDay: picked.day,
      ),
    );
  }

  Widget _genderField() {
    return SizedBox(
      height: appPickerFieldHeight,
      child: DropdownButtonFormField<ProfileGender>(
        key: const ValueKey<String>('gender-field'),
        initialValue: accountDraft.gender,
        isExpanded: true,
        style: const AppTextStyle(fontSize: 14, color: AppColors.textPrimary),
        icon: appPickerArrow,
        dropdownColor: AppColors.surfacePrimary,
        decoration: appPickerDecoration(hintText: '성별 선택'),
        items: const [
          DropdownMenuItem(value: ProfileGender.male, child: Text('남성')),
          DropdownMenuItem(value: ProfileGender.female, child: Text('여성')),
          DropdownMenuItem(value: ProfileGender.other, child: Text('선택 안 함')),
        ],
        onChanged: submitting
            ? null
            : (value) {
                if (value != null) {
                  onAccountChanged(accountDraft.copyWith(gender: value));
                }
              },
      ),
    );
  }
}

/// The agreements, asked in a sheet over the setup page once its questions
/// are answered. The start button is live once the required ones are
/// checked; while the save runs nothing in the sheet can be pressed again.
class _AgreementsSheet extends StatelessWidget {
  const _AgreementsSheet({
    required this.account,
    required this.submitting,
    required this.saveFailed,
    required this.saveError,
    required this.onChanged,
    required this.onStart,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
  });

  final AccountCompletionDraft account;
  final bool submitting;
  final bool saveFailed;
  final Object? saveError;

  final ValueChanged<_AgreementChange> onChanged;
  final VoidCallback onStart;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;

  ValueChanged<bool>? _agreement(
    AccountCompletionDraft Function(AccountCompletionDraft draft, bool value)
    change,
  ) =>
      submitting ? null : (value) => onChanged((draft) => change(draft, value));

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: appSheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AppSheetHeading(title: '약관에 동의해 주세요'),
          const SizedBox(height: AppSpacing.md),
          _AgreementRow(
            key: const ValueKey<String>('all-agreements-row'),
            label: '약관 전체 동의',
            value: account.hasRequiredAgreements,
            emphasized: true,
            onChanged: _agreement(
              (draft, value) => draft.withAllAgreements(value),
            ),
          ),
          const Divider(height: 1, color: AppColors.borderSubtle),
          _AgreementRow(
            key: const ValueKey<String>('adult-agreement-row'),
            label: '[필수] 만 19세 이상 성인 확인',
            value: account.adultAgeConfirmed,
            onChanged: _agreement(
              (draft, value) => draft.copyWith(adultAgeConfirmed: value),
            ),
          ),
          _AgreementRow(
            key: const ValueKey<String>('terms-agreement-row'),
            label: '[필수] 서비스 이용약관 동의',
            value: account.termsAccepted,
            onChanged: _agreement(
              (draft, value) => draft.copyWith(termsAccepted: value),
            ),
            onOpenDocument: onOpenTerms,
          ),
          _AgreementRow(
            key: const ValueKey<String>('privacy-agreement-row'),
            label: '[필수] 개인정보 수집 및 이용 동의',
            value: account.privacyAccepted,
            onChanged: _agreement(
              (draft, value) => draft.copyWith(privacyAccepted: value),
            ),
            onOpenDocument: onOpenPrivacy,
          ),
          _AgreementRow(
            key: const ValueKey<String>('marketing-agreement-row'),
            label: '[선택] 광고성 정보 앱 알림 수신 동의',
            value: account.marketingOptIn,
            onChanged: _agreement(
              (draft, value) => draft.copyWith(marketingOptIn: value),
            ),
          ),
          if (saveFailed) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              failureLine(saveError, '프로필 설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'),
              key: const ValueKey<String>('profile-setup-save-feedback'),
              style: AppTextStyles.body.copyWith(
                color: AppColors.actionPrimary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            key: const ValueKey<String>('complete-signup-button'),
            label: submitting ? '가입하는 중...' : '술결 시작하기',
            onPressed: account.hasRequiredAgreements && !submitting
                ? onStart
                : null,
            variant: AppButtonVariant.accent,
            size: AppButtonSize.sheet,
          ),
        ],
      ),
    );
  }
}

class _AgreementRow extends StatelessWidget {
  const _AgreementRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.emphasized = false,
    this.onOpenDocument,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool emphasized;
  final VoidCallback? onOpenDocument;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          0,
          AppSpacing.xxs,
          0,
          AppSpacing.xxs,
        ),
        child: Row(
          children: <Widget>[
            Checkbox(
              value: value,
              onChanged: onChanged == null
                  ? null
                  : (next) => onChanged!(next ?? false),
              activeColor: AppColors.actionPrimary,
            ),
            Expanded(
              child: Text(
                label,
                style: AppTextStyle(
                  fontSize: emphasized ? 15 : 14,
                  fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (onOpenDocument != null)
              IconButton(
                onPressed: onOpenDocument,
                tooltip: '약관 전문 보기',
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A step that was just asked for: it opens at the top of the page, moving
/// the answered ones down, and fades in while rising a little into its
/// place. With [animate] off, or reduced motion, it is simply there.
class _Appearing extends StatelessWidget {
  const _Appearing({required this.animate, required this.child, super.key});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate || MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppDurations.slow,
      curve: Curves.easeOut,
      builder: (context, shown, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: shown,
          child: Opacity(
            opacity: shown,
            child: Transform.translate(
              offset: Offset(0, (1 - shown) * AppSpacing.md),
              child: child,
            ),
          ),
        ),
      ),
      child: child,
    );
  }
}
