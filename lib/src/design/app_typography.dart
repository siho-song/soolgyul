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

  /// 화면에서 가장 크게 강조하는 대표 제목에 사용합니다.
  static const displayTitle = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

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

  /// 일반적인 화면 내 콘텐츠 구역을 구분할 때 사용합니다.
  static const sectionTitleMd = TextStyle(
    fontSize: 16,
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

  /// 질문 제목 아래의 조용한 안내 줄과 그 끝의 `0/5` 같은 개수에 사용합니다.
  static const descriptionTrailing = TextStyle(
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w500,
    color: Color(0xFF767676),
  );

  /// 섹션 제목 오른쪽의 자세히 보기·더보기 동작에 사용합니다.
  static const sectionAction = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.actionPrimaryStrong,
  );

  /// 주요 구역 안에서 한 단계 아래의 콘텐츠 묶음을 구분할 때 사용합니다.
  static const sectionSubtitle = TextStyle(
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
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

  /// 화면이나 목록을 불러오지 못했을 때 무엇이 실패했는지 알리는 한 줄입니다.
  static const stateTitle = TextStyle(
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// 상태 화면의 제목 아래에서 다음 행동을 안내하는 연한 한 줄입니다.
  static const stateDescription = TextStyle(
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

  /// 보조 설명처럼 작은 본문 문구에 사용합니다.
  static const bodySmall = TextStyle(
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  /// 술 기록 질문의 제목 아래에서 질문의 맥락을 설명할 때 사용합니다.
  static const recordingQuestionDescription = TextStyle(
    fontSize: 13,
    height: 1.55,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// 화면 안에서 별도로 노출되는 간단한 설문의 질문에 사용합니다.
  static const surveyQuestion = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 18,
    height: 1.35,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  /// 설문 응답이 어떻게 활용되는지 안내하는 문구에 사용합니다.
  static const surveyDescription = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w600,
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

  /// 도움말 카드 우측의 짧은 텍스트 액션에 사용합니다.
  static const supportAction = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 11,
    height: 1.4,
    letterSpacing: -0.1,
    fontWeight: FontWeight.w500,
    color: AppColors.supportSecondary,
  );

  /// 자주 묻는 질문의 각 질문 문구에 사용합니다.
  static const supportQuestion = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 12,
    height: 1.45,
    letterSpacing: -0.2,
    fontWeight: FontWeight.w600,
    color: AppColors.supportInk,
  );

  /// 도움말·문의 카드의 대표 제목에 사용합니다.
  static const supportCardTitle = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 13,
    height: 1.4,
    letterSpacing: -0.15,
    fontWeight: FontWeight.w700,
    color: AppColors.supportInk,
  );

  /// 도움말·문의 화면의 보조 설명에 사용합니다.
  static const supportBody = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 12,
    height: 1.65,
    letterSpacing: -0.1,
    fontWeight: FontWeight.w500,
    color: AppColors.supportSecondary,
  );

  /// 도움말·문의 화면 최상단의 두 줄 설명에 사용합니다.
  static const supportPageDescription = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 12,
    height: 1.85,
    letterSpacing: -0.1,
    fontWeight: FontWeight.w500,
    color: AppColors.supportSecondary,
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
    color: AppColors.supportInk,
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

  /// 문의 글자 수와 첨부 수처럼 작은 수치 안내에 사용합니다.
  static const supportCounter = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 9,
    height: 1.4,
    fontWeight: FontWeight.w500,
    color: AppColors.supportSecondary,
  );

  /// 문의 전송 버튼의 문구에 사용합니다.
  static const supportSubmit = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 13,
    height: 1.2,
    letterSpacing: 0.35,
    fontWeight: FontWeight.w600,
    color: AppColors.textOnPrimary,
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

  /// 온보딩 화면에서 본문보다 조금 강조된 도입 문구에 사용합니다.
  static const onboardingLead = TextStyle(
    fontSize: 14,
    height: 1.5,
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

  /// 선택된 온보딩 선택지의 라벨에 사용합니다.
  static const onboardingOptionLabelSelected = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 14,
    height: 1.4,
    color: AppColors.actionPrimary,
    fontWeight: FontWeight.w800,
  );

  /// 온보딩 선택지 아래의 보조 설명에 사용합니다.
  static const onboardingOptionDescription = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 14,
    height: 1.45,
    color: AppColors.textSecondary,
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

  /// 작은 크기 버튼의 텍스트에 사용합니다.
  static const buttonLabelCompact = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 14,
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

  /// 홈 화면의 섹션 제목 아래 설명 문구에 사용합니다.
  ///
  /// 화면의 기능을 설명하는 [pageDescription]과 의미가 다르므로 별도로
  /// 관리합니다.
  static const homeWelcomeMessage = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 12,
    height: 1.5,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  /// 홈 카드의 취향 방향 안내 문구에 사용합니다.
  static const homeCardSupporting = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSupporting,
  );

  /// 홈의 다음 한 잔 제안에서 현재 페이지를 표시할 때 사용합니다.
  static const homeSuggestionPosition = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  /// 홈의 다음 한 잔 제안 제목에 사용합니다.
  static const homeSuggestionTitle = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

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

  /// 나의 취향 조각 요약 카드의 안내 문구에 사용합니다.
  static const homeLettersOverviewBody = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
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

  /// 나의 취향 조각 의미 카드의 설명에 사용합니다.
  static const homeLetterMeaningBody = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 12,
    height: 1.55,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  /// 아직 드러나지 않은 글자를 설명하는 강조 문구에 사용합니다.
  static const homeUnknownLetterEmphasis = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 13,
    height: 1.7,
    fontWeight: FontWeight.w600,
    color: AppColors.textWarmSecondary,
  );

  // --- History calendar and records ---

  /// 히스토리 달력 상단의 현재 연월 제목에 사용합니다.
  static const historyMonthTitle = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// 히스토리 월 선택 창에서 연도를 표시할 때 사용합니다.
  static const historyYearTitle = TextStyle(
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// 히스토리 달력의 일·월·화·수·목·금·토 요일에 사용합니다.
  static const historyWeekday = TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

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

  /// 히스토리 기록 카드의 술 이름에 사용합니다.
  static const historyRecordTitle = TextStyle(
    fontSize: 19,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// 히스토리 기록 카드의 주종과 기록 시간에 사용합니다.
  static const historyRecordMeta = TextStyle(
    fontSize: 12,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textWarmTertiary,
  );

  /// 히스토리 기록 카드에서 칩 아래에 이어지는 술결 카드의 한 줄 요약에 사용합니다.
  static const historyRecordSummary = TextStyle(
    fontSize: 12,
    height: 1.55,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  /// 히스토리 월간 요약 카드의 기본 설명에 사용합니다.
  static const historySummaryBody = TextStyle(
    fontSize: 14,
    height: 1.6,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  /// 선택한 날짜에 기록이 없을 때 표시하는 안내 문구에 사용합니다.
  static const historyEmptyState = TextStyle(
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );
}
