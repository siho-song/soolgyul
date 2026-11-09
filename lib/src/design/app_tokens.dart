import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const textPrimary = Color(0xFF161616);
  static const textSecondary = Color(0xFF666666);
  static const textTertiary = Color(0xFF777777);
  static const textSupporting = Color(0xFF555555);
  static const textStrong = Color(0xFF333333);
  static const textWarmSecondary = Color(0xFF5F5B58);
  static const textWarmTertiary = Color(0xFF8A7A71);
  static const textOnPrimary = Color(0xFFFFFFFF);

  static const borderSubtle = Color(0xFFE7E1DC);
  static const borderMuted = Color(0xFFE9DED7);
  static const borderControl = Color(0xFFE6DDD8);
  static const borderStrong = Color(0xFFD9CFC8);

  static const actionPrimary = Color(0xFF6F1422);
  static const actionPrimaryStrong = Color(0xFF521018);
  static const actionNeutral = Color(0xFFDDD8D3);
  static const actionDestructive = Color(0xFFB3261E);
  static const controlInactive = Color(0xFFD6D2CF);

  // Shared app-header and help reference-screen colors.
  static const headerTitle = Color(0xFF5F1010);
  static const supportButton = Color(0xFF521211);
  static const supportInk = Color(0xFF141413);
  static const supportSecondary = Color(0xFF626161);
  static const supportPlaceholder = Color(0xFF9C9B9B);
  static const supportIconWarm = Color(0xFF978674);
  static const supportIconSurface = Color(0xFFFAF4EF);

  static const surfaceCanvas = Color.fromRGBO(251, 246, 240, 1);
  static const surfacePrimary = Color(0xFFFFFFFF);

  /// 홈 카드를 기준으로 정한 앱 전역 기본 카드 배경색입니다.
  static const surfaceCard = Color.fromRGBO(252, 247, 242, 1);
  static const surfaceSoft = Color(0xFFF8F3EE);
  static const surfaceMuted = Color(0xFFF0ECE8);
  static const scrim = Color(0x94000000);
  static const scrimStrong = Color(0x99000000);

  // Saved-content collection chips.
  static const collectionChipSurface = Color(0xFFFCF8F5);
  static const collectionChipBorder = Color(0xFFE8DDD8);
  static const collectionChipText = Color(0xFF651D27);
  static const collectionTagSurface = Color(0xFFF7F1EF);
  static const collectionTagText = Color(0xFF765054);

  // Profile interest selection.
  static const profileInterestSelectedSurface = Color(0xFFF7EEEE);
  static const profileInterestSelectedBorder = Color(0xFFCAA9AC);
  static const profileInterestBorder = Color(0xFFE6D8CF);
  static const profileInterestSelectedIconSurface = Color(0xFFF8EAE8);
  static const profileInterestIconSurface = Color(0xFFF8F1EB);
  static const profileInterestShadow = Color(0x0D6A3429);

  // Home taste-letter and supporting-card colors.
  static const homeLetterWine = Color(0xFF7C1E35);
  static const homeLetterOlive = Color(0xFF4D5B2B);
  static const homeLetterUnknown = Color(0xFF969088);
  static const homeGuidanceWineSurface = Color(0xFFF8ECEB);
  static const homeGuidanceWineBorder = Color(0xFFEAD7D4);
  static const homeGuidanceOliveSurface = Color(0xFFF2F2E6);
  static const homeGuidanceOliveBorder = Color(0xFFDEDFCC);

  static const preferencePrimary = Color(0xFF2D4B38);
  static const preferencePrimaryStrong = Color(0xFF1F3A2B);

  static const exploreEditorialIndicator = Color(0xFFD8D2CE);
  static const exploreEditorialChipBorder = Color(0xFFE3DED9);
}

class AppDataColors {
  const AppDataColors._();

  static const wine = AppColors.actionPrimary;
  static const whisky = Color(0xFFC87905);
  static const sake = Color(0xFF5D91B5);
  static const traditional = Color(0xFF7FA065);
  static const other = Color(0xFF8A8A8A);
}

class AppFonts {
  const AppFonts._();

  static const display = 'MaruBuri';
  static const body = 'MaruBuri';

  /// Only the emoji the app writes, cut from Noto Color Emoji. Phones draw
  /// emoji from their own font; a browser has none, and without this the
  /// web engine fetched the whole Noto emoji font from Google the first
  /// time an emoji appeared, showing boxes until it arrived.
  static const emoji = 'NotoColorEmoji';

  static const fallback = kIsWeb ? <String>[emoji] : <String>[];
}

class AppRadii {
  const AppRadii._();

  static const control = 14.0;
  static const compactCard = 18.0;
  static const card = 22.0;
  static const largeCard = 26.0;
  static const chip = 999.0;
  static const sheet = 26.0;
  static const heroMedia = 24.0;
}

class AppSpacing {
  const AppSpacing._();

  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 40.0;
  static const massive = 48.0;
  static const screenX = 22.0;
  static const sheetX = 24.0;
  static const navHeight = 78.0;

  static const pageDescriptionToContent = 18.0;
}

class AppSizes {
  const AppSizes._();

  static const minimumTapTarget = 44.0;
  static const headerHeight = 64.0;
  static const headerButton = 48.0;
  static const headerIcon = 24.0;
  static const menuRowHeight = 52.0;
  static const iconSmall = 16.0;
  static const iconMedium = 24.0;
  static const iconLarge = 32.0;
}

class AppDurations {
  const AppDurations._();

  static const fast = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 200);
}

class AppShadows {
  const AppShadows._();

  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x0D6F4A35), blurRadius: 10, spreadRadius: .1),
    BoxShadow(color: Color(0x086F4A35), blurRadius: 22, offset: Offset(0, 6)),
  ];

  static const floatingControl = <BoxShadow>[
    BoxShadow(color: Color(0x16000000), blurRadius: 18, offset: Offset(0, 6)),
  ];

  static const homeLetterStrip = <BoxShadow>[
    BoxShadow(color: Color(0x26000000), blurRadius: 5, offset: Offset(0, 2)),
  ];

  static const homeLetterTile = <BoxShadow>[
    BoxShadow(color: Color(0x18000000), blurRadius: 5, offset: Offset(0, 2)),
  ];

  static const homeGuidanceHighlight = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3)),
  ];

  static const profileInterestCard = <BoxShadow>[
    BoxShadow(
      color: AppColors.profileInterestShadow,
      blurRadius: 8,
      offset: Offset(0, 3),
    ),
  ];

  static const searchResults = <BoxShadow>[
    BoxShadow(color: Color(0x0D000000), blurRadius: 20, offset: Offset(0, 8)),
  ];
}
