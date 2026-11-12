import '../../../../widgets/app_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../design/app_layout.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_surface.dart';
import '../../../../widgets/app_text_field.dart';
import '../../../profile/data/account_completion_draft.dart';
import '../../../profile/data/drink_interest_catalog.dart';
import '../../../profile/data/profile_setup_draft.dart';
import '../widgets/onboarding_actions.dart';
import '../widgets/onboarding_buttons.dart';
import 'birth_date_picker.dart';

/// The one post-login setup page: nickname, drink interests, birth date,
/// gender and the agreements, saved together by the start button.
class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({
    required this.profileDraft,
    required this.onProfileChanged,
    required this.accountDraft,
    required this.onAccountChanged,
    required this.onComplete,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
    this.submitting = false,
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

  bool get _canStart =>
      profileDraft.hasValidDisplayName &&
      profileDraft.hasValidDrinkInterests &&
      accountDraft.canComplete &&
      !submitting;

  ValueChanged<bool>? _agreement(
    AccountCompletionDraft Function(bool value) change,
  ) => submitting ? null : (value) => onAccountChanged(change(value));

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
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  layout.horizontalPadding,
                  AppSpacing.xl,
                  layout.horizontalPadding,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      '술결을 시작해 볼까요?',
                      style: AppTextStyle(
                        fontSize: 24,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontFamily: AppFonts.display,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      '나만의 술결을 기록할 프로필을 만들어 보세요.',
                      style: AppTextStyles.body,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionTitle('닉네임'),
                    const SizedBox(height: AppSpacing.s10),
                    _nicknameField(),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionTitle('관심 주종', hint: '(여러 개 골라도 괜찮아요)'),
                    const SizedBox(height: AppSpacing.s10),
                    _interestGrid(gap, tileWidth),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionTitle('기본 정보'),
                    const SizedBox(height: AppSpacing.s10),
                    _basicInfoRow(context),
                    const SizedBox(height: AppSpacing.lg),
                    _agreementsCard(),
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
                  key: const ValueKey<String>('complete-signup-button'),
                  label: submitting ? '가입하는 중...' : '술결 시작하기',
                  onPressed: _canStart ? onComplete : null,
                ),
              ),
            ),
          ],
        );
      },
    );
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

  Widget _nicknameField() {
    final length = profileDraft.displayName.characters.length;
    return SizedBox(
      height: 54,
      child: Stack(
        children: <Widget>[
          AppTextField(
            initialValue: profileDraft.displayName,
            maxLength: ProfileSetupDraft.maximumDisplayNameLength,
            textInputAction: TextInputAction.done,
            hintText: '예) 위스키사랑, 밤바다한잔',
            size: AppTextFieldSize.compact,
            enabled: !submitting,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(
                RegExp(r'[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ]'),
              ),
            ],
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

  Widget _basicInfoRow(BuildContext context) {
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
            onTap: submitting ? null : () => _pickBirthDate(context),
          ),
        ),
        const SizedBox(width: AppSpacing.s10),
        Expanded(flex: 7, child: _genderField()),
      ],
    );
  }

  Future<void> _pickBirthDate(BuildContext context) async {
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

  Widget _agreementsCard() {
    return AppSurface(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      borderRadius: AppRadii.compactCard,
      variant: AppSurfaceVariant.card,
      child: Column(
        children: <Widget>[
          _AgreementRow(
            key: const ValueKey<String>('all-agreements-row'),
            label: '약관 전체 동의',
            value: accountDraft.hasRequiredAgreements,
            emphasized: true,
            onChanged: _agreement(accountDraft.withAllAgreements),
          ),
          const Divider(height: 1, color: AppColors.borderSubtle),
          _AgreementRow(
            key: const ValueKey<String>('adult-agreement-row'),
            label: '[필수] 만 19세 이상 성인 확인',
            value: accountDraft.adultAgeConfirmed,
            onChanged: _agreement(
              (value) => accountDraft.copyWith(adultAgeConfirmed: value),
            ),
          ),
          _AgreementRow(
            key: const ValueKey<String>('terms-agreement-row'),
            label: '[필수] 서비스 이용약관 동의',
            value: accountDraft.termsAccepted,
            onChanged: _agreement(
              (value) => accountDraft.copyWith(termsAccepted: value),
            ),
            onOpenDocument: onOpenTerms,
          ),
          _AgreementRow(
            key: const ValueKey<String>('privacy-agreement-row'),
            label: '[필수] 개인정보 수집 및 이용 동의',
            value: accountDraft.privacyAccepted,
            onChanged: _agreement(
              (value) => accountDraft.copyWith(privacyAccepted: value),
            ),
            onOpenDocument: onOpenPrivacy,
          ),
          _AgreementRow(
            key: const ValueKey<String>('marketing-agreement-row'),
            label: '[선택] 광고성 정보 앱 알림 수신 동의',
            value: accountDraft.marketingOptIn,
            onChanged: _agreement(
              (value) => accountDraft.copyWith(marketingOptIn: value),
            ),
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
