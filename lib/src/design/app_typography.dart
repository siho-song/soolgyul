import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// The common base for intentional one-off text styles.
///
/// Prefer a semantic role from [AppTextStyles]. Use this class only when a
/// screen needs a measured variant that is not yet shared by another screen.
class AppTextStyle extends TextStyle {
  const AppTextStyle({
    super.fontSize,
    super.fontWeight,
    super.height,
    super.letterSpacing,
    super.color = AppColors.textPrimary,
    super.fontFamily = AppFonts.body,
    super.fontFamilyFallback = AppFonts.fallback,
  });
}

class AppTextStyles {
  const AppTextStyles._();

  // --- Shared titles ---

  /// 각 화면의 본문 최상단 페이지 제목에 사용합니다.
  static const screenTitle = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  /// 앱의 모든 공통 헤더 제목에 사용합니다.
  static const appHeaderTitle = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 17,
    height: 1.1,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  /// 한 화면 안에서 가장 큰 콘텐츠 구역을 구분할 때 사용합니다.
  static const sectionTitle = TextStyle(
    fontSize: 18,
    height: 1.35,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  /// 밀도가 높은 화면의 작은 콘텐츠 구역을 구분할 때 사용합니다.
  static const sectionTitleSm = TextStyle(
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  /// 섹션 제목 오른쪽의 자세히 보기·더보기 동작에 사용합니다.
  static const sectionAction = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.actionPrimaryStrong,
  );

  /// 카드 내부의 대표 제목에 사용합니다.
  static const cardTitle = TextStyle(
    fontSize: 16,
    height: 1.4,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  /// 마이페이지와 설정 화면의 메뉴 항목 제목에 사용합니다.
  static const menuItemTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  // --- Shared body, input and label text ---

  /// 일반 본문보다 조금 크고 강조된 설명 문구에 사용합니다.
  static const bodyLarge = TextStyle(
    fontSize: 14,
    height: 1.55,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
  );

  /// 목록 항목이나 상태 화면처럼 작은 덩어리의 제목에 사용합니다.
  static const itemTitle = TextStyle(
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// 제목 옆이나 아래에 붙는 연한 설명에 사용합니다.
  static const bodyMuted = TextStyle(
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
  );

  /// 화면과 카드에서 사용하는 기본 본문 문구에 사용합니다.
  static const body = TextStyle(
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  /// 기본 입력창에 사용자가 입력한 문구에 사용합니다.
  static const textFieldText = TextStyle(
    fontSize: 14,
    height: 1.55,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  /// 기본 입력창에 아직 값이 없을 때 표시하는 힌트 문구에 사용합니다.
  static const textFieldHint = TextStyle(
    fontSize: 14,
    height: 1.55,
    fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
  );

  /// 술 기록 질문의 제목 아래에서 질문의 맥락을 설명할 때 사용합니다.
  static const recordingQuestionDescription = TextStyle(
    fontSize: 13,
    height: 1.55,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// 작은 상태값이나 짧은 보조 라벨에 사용합니다.
  static const labelSmall = TextStyle(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
  );

  /// 가장 낮은 단계의 부가 정보와 안내 문구에 사용합니다.
  static const caption = TextStyle(
    fontSize: 11,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
  );

  // --- Support center ---

  /// 도움말·문의 화면의 레퍼런스에 맞춘 와인색 구역 제목입니다.
  static const supportSectionTitle = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 15,
    height: 1.35,
    letterSpacing: -0.15,
    fontWeight: FontWeight.w700,
    color: AppColors.headerTitle,
  );

  /// 도움말·문의 카드의 대표 제목에 사용합니다.
  static const supportCardTitle = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 13,
    height: 1.4,
    letterSpacing: -0.15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// 문의 작성 폼의 필드 이름에 사용합니다.
  static const supportFieldLabel = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 12,
    height: 1.4,
    letterSpacing: -0.1,
    fontWeight: FontWeight.w700,
    color: AppColors.headerTitle,
  );

  /// 문의 작성 폼의 입력값에 사용합니다.
  static const supportFieldText = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 12,
    height: 1.5,
    letterSpacing: -0.15,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  /// 문의 작성 폼의 플레이스홀더에 사용합니다.
  static const supportFieldHint = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 12,
    height: 1.5,
    letterSpacing: -0.1,
    fontWeight: FontWeight.w500,
    color: AppColors.supportPlaceholder,
  );

  // --- Onboarding ---

  /// 온보딩 화면의 가장 큰 질문 또는 안내 제목에 사용합니다.
  static const onboardingTitle = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 23,
    height: 1.35,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  /// 온보딩 화면의 기본 설명 문구에 사용합니다.
  static const onboardingBody = TextStyle(
    fontSize: 14,
    height: 1.55,
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w400,
  );

  /// 온보딩 선택지의 기본 라벨에 사용합니다.
  static const onboardingOptionLabel = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 14,
    height: 1.4,
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  static const onboardingOptionLabelSelected = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 14,
    height: 1.4,
    color: AppColors.actionPrimary,
    fontWeight: FontWeight.w800,
  );

  // --- Modals and buttons ---

  /// 모달과 바텀 시트의 설명 문구에 사용합니다.
  static const modalBody = TextStyle(
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  /// 기본 크기 버튼의 텍스트에 사용합니다.
  static const buttonLabel = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 16,
    color: AppColors.textOnPrimary,
    fontWeight: FontWeight.w700,
  );

  // --- Profile ---

  /// 마이페이지 프로필 영역의 사용자 닉네임에 사용합니다.
  static const profileName = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  // --- Home ---

  /// 취향 조각 요약 카드의 사용자 이름을 포함한 제목에 사용합니다.
  static const homeLettersOverviewTitle = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w800,
    color: AppColors.actionPrimaryStrong,
  );

  /// 취향 조각 요약 카드의 한 문장 해석에 사용하는 기본 스타일입니다.
  static const homeLettersOverviewStatement = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 16,
    height: 1.55,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  /// 취향 조각 요약 문장에서 I 방향을 강조할 때 사용합니다.
  static const homeLettersOverviewWine = TextStyle(
    color: AppColors.homeLetterWine,
  );

  /// 취향 조각 요약 문장에서 S 방향을 강조할 때 사용합니다.
  static const homeLettersOverviewOlive = TextStyle(
    color: AppColors.homeLetterOlive,
  );

  /// 술결 글자 타일 아래의 축 이름(향·단맛·무게·여운)에 사용합니다.
  static const homeLetterCaption = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w500,
    color: AppColors.homeLetterUnknown,
  );

  /// 술결 글자 타일의 크기와 색상에 맞는 글자 스타일을 만듭니다.
  static TextStyle homeLetter({
    required double fontSize,
    required Color color,
  }) {
    return TextStyle(
      fontFamily: AppFonts.body,
      fontSize: fontSize,
      height: 1,
      fontWeight: FontWeight.w700,
      color: color,
    );
  }

  /// 나의 취향 조각 의미 카드의 제목 스타일을 만듭니다.
  static TextStyle homeLetterMeaningTitle(Color color) {
    return TextStyle(
      fontFamily: AppFonts.body,
      fontSize: 17,
      height: 1.3,
      fontWeight: FontWeight.w800,
      color: color,
    );
  }

  /// 카드 안의 작은 설명 문단에 사용합니다.
  static const detail = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 12,
    height: 1.55,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  // --- History calendar and records ---

  /// 히스토리 달력의 일반 화면 날짜 숫자에 사용하는 기본 스타일입니다.
  static const _historyCalendarDay = TextStyle(
    fontSize: 15,
    height: 1,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  /// 히스토리 달력의 좁은 화면 날짜 숫자에 사용하는 기본 스타일입니다.
  static const _historyCalendarDayCompact = TextStyle(
    fontSize: 13,
    height: 1,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  /// 화면 폭과 날짜의 선택·비활성 상태에 맞는 달력 날짜 스타일을 만듭니다.
  static TextStyle historyCalendarDay({
    required bool compact,
    required bool selected,
    required bool muted,
  }) {
    return (compact ? _historyCalendarDayCompact : _historyCalendarDay)
        .copyWith(
          color: muted ? const Color(0xFFCEC5BE) : AppColors.textPrimary,
          fontWeight: selected ? FontWeight.w800 : null,
        );
  }

  /// 하루 기록이 네 개 이상일 때 물결 옆의 `+1` 표시에 사용합니다.
  static const historyCalendarOverflow = TextStyle(
    fontSize: 8,
    height: 1,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
  );

  /// 히스토리 기록 카드의 주종과 기록 시간에 사용합니다.
  static const historyRecordMeta = TextStyle(
    fontSize: 12,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textWarmTertiary,
  );
}
