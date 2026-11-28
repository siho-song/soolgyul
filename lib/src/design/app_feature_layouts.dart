import 'app_tokens.dart';

/// 홈 탭 루트 화면의 콘텐츠 간격 규격입니다.
abstract final class HomeLayoutSpacing {
  static const cardGap = AppSpacing.md;
  static const sectionGap = AppSpacing.xxl;
}

/// 기록 탭 루트 화면의 콘텐츠 간격 규격입니다.
abstract final class PreferenceLayoutSpacing {
  static const contentHorizontal = AppSpacing.screenX;
  static const sectionToContent = AppSpacing.lg;
  static const sectionGap = AppSpacing.xl;
}

/// 마이페이지 루트 화면의 프로필·섹션·카드 간격 규격입니다.
abstract final class ProfileLayoutSpacing {
  // From the account's lines at the top of the tab to its first section.
  static const heroToContent = AppSpacing.xxxl;
  static const sectionToContent = AppSpacing.md;
  static const sectionGap = AppSpacing.xxl;
  static const bottom = AppSpacing.xxl;
}
