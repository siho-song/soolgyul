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
                  20,
                  layout.horizontalPadding,
                  16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      '술결을 시작해볼까요?',
                      style: AppTextStyle(
                        fontSize: 24,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontFamily: AppFonts.display,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '나만의 술결을 기록할 프로필을 완성해보세요.',
                      style: AppTextStyles.body,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionTitle('닉네임'),
                    const SizedBox(height: 10),
                    _nicknameField(),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionTitle('관심 있는 술', hint: '(다양하게 골라도 좋아요)'),
                    const SizedBox(height: 10),
                    _interestGrid(gap, tileWidth),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionTitle('기본 정보'),
                    const SizedBox(height: 10),
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
                  8,
                  layout.horizontalPadding,
                  20,
                ),
                child: OnboardingPrimaryButton(
                  key: const ValueKey<String>('complete-signup-button'),
                  label: submitting ? '가입 중...' : '술결 시작하기',
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
          const SizedBox(width: 6),
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
            hintText: '위스키사랑, 밤바다한잔',
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
          child: _PickerField(
            key: const ValueKey<String>('birth-date-field'),
            icon: AppIconAsset.calendar,
            label: birthDate == null
                ? '생년월일 선택'
                : '${birthDate.year}년 ${birthDate.month}월 ${birthDate.day}일',
            filled: birthDate != null,
            onTap: submitting ? null : () => _pickBirthDate(context),
          ),
        ),
        const SizedBox(width: 10),
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
      height: 54,
      child: DropdownButtonFormField<ProfileGender>(
        key: const ValueKey<String>('gender-field'),
        initialValue: accountDraft.gender,
        isExpanded: true,
        style: const AppTextStyle(fontSize: 14, color: AppColors.textPrimary),
        iconSize: 20,
        decoration: const InputDecoration(
          hintText: '성별',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        ),
        items: const [
          DropdownMenuItem(value: ProfileGender.male, child: Text('남성')),
          DropdownMenuItem(value: ProfileGender.female, child: Text('여성')),
          DropdownMenuItem(value: ProfileGender.other, child: Text('기타')),
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
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      borderRadius: AppRadii.compactCard,
      variant: AppSurfaceVariant.card,
      child: Column(
        children: <Widget>[
          _AgreementRow(
            key: const ValueKey<String>('all-agreements-row'),
            label: '전체 동의하기',
            value: accountDraft.hasRequiredAgreements,
            emphasized: true,
            onChanged: _agreement(accountDraft.withAllAgreements),
          ),
          const Divider(height: 1, color: AppColors.borderSubtle),
          _AgreementRow(
            key: const ValueKey<String>('adult-agreement-row'),
            label: '[필수] 만 19세 이상 성인입니다',
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
            label: '[선택] 혜택 및 추천 알림 수신 동의',
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

/// A tappable field that looks like the app's text field and opens a picker.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
    super.key,
  });

  final AppIconAsset icon;
  final String label;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = filled ? AppColors.textPrimary : AppColors.textTertiary;
    return SizedBox(
      height: 54,
      child: Material(
        color: AppColors.surfacePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          side: const BorderSide(color: AppColors.borderControl),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
            child: Row(
              children: <Widget>[
                AppIcon(icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle(fontSize: 14, color: color),
                  ),
                ),
                Icon(
                  Icons.expand_more,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
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
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
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
                tooltip: '상세 보기',
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
