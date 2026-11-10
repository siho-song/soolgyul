import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/editorial/data/editorial_article_save_state.dart';
import '../features/onboarding/presentation/widgets/onboarding_buttons.dart';
import '../features/onboarding/presentation/sensory_questionnaire_screen.dart';
import '../design/app_tokens.dart';
import '../navigation/app_route.dart';
import '../widgets/app_brand_logo.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_top_bar.dart';

abstract final class AppHeaderPolicy {
  static AppTopBar _onboardingStepHeader(
    VoidCallback onBack, {
    List<Widget> actions = const <Widget>[],
  }) {
    return AppTopBar.back(
      onPressed: onBack,
      center: const OnboardingBrandHeader(centered: true),
      actions: actions,
    );
  }

  /// SKIP for the question screens, only while the shown question allows it.
  static List<Widget> _skipActions(ValueListenable<SensorySkip?>? skip) =>
      skip == null
      ? const <Widget>[]
      : <Widget>[SensorySkipHeaderAction(skip: skip)];

  static AppTopBar _resultHeader({
    required VoidCallback? onBack,
    required List<Widget> actions,
  }) {
    const logo = OnboardingBrandHeader(centered: true);
    if (onBack == null) {
      return AppTopBar.logo(
        logo: logo,
        logoAlignment: Alignment.center,
        actions: actions,
      );
    }
    return AppTopBar.back(onPressed: onBack, center: logo, actions: actions);
  }

  static const AppTopBar _mainTabHeader = AppTopBar.logo(
    logo: AppBrandLogo(size: AppBrandLogoSize.medium),
    logoAlignment: Alignment.center,
  );

  static PreferredSizeWidget? build({
    required AppRoute route,
    required VoidCallback onBack,
    required ValueChanged<EditorialArticleSaveState> onEditorialSave,
    EditorialArticleSaveState? editorialSave,
    VoidCallback? onEditorialInstagram,
    ValueListenable<SensorySkip?>? sensorySkip,
    List<Widget> resultActions = const <Widget>[],
    bool resultShowsSavedCard = false,
  }) {
    return switch (route) {
      AppRoute.appLoading => null,
      AppRoute.appLogin => const AppTopBar.logo(
        logo: OnboardingBrandHeader(centered: true),
        logoAlignment: Alignment.center,
      ),
      AppRoute.onboardingWelcome => const AppTopBar.logo(
        logo: OnboardingBrandHeader(),
        logoAlignment: Alignment.center,
      ),
      // A record after the first walks the same pages under the same
      // header as the first one.
      AppRoute.onboardingSearch ||
      AppRoute.onboardingQuestions ||
      AppRoute.recordSearch ||
      AppRoute.recordQuestions => _onboardingStepHeader(
        onBack,
        actions: _skipActions(sensorySkip),
      ),
      AppRoute.profileSetup => _onboardingStepHeader(onBack),
      // A saved card's header carries its 좋아요 and 더보기; one opened again
      // from a list also leads back to it.
      AppRoute.onboardingResult => _resultHeader(
        onBack: resultShowsSavedCard ? onBack : null,
        actions: resultActions,
      ),
      AppRoute.home ||
      AppRoute.recordEntry ||
      AppRoute.explore => _mainTabHeader,
      AppRoute.preference || AppRoute.profile || AppRoute.designLab => null,
      AppRoute.soolgyulLetters => AppTopBar.back(
        onPressed: onBack,
        title: '취향 카드',
        showDivider: true,
      ),
      AppRoute.supportCenter => AppTopBar.back(
        onPressed: onBack,
        title: '도움말 및 문의',
      ),
      AppRoute.supportInquiry => AppTopBar.back(
        onPressed: onBack,
        title: '문의하기',
      ),
      AppRoute.policy => AppTopBar.back(onPressed: onBack, title: '약관 및 개인정보'),
      AppRoute.tasteFitSearch => AppTopBar.back(
        onPressed: onBack,
        title: '나랑 맞는 술 찾기',
      ),
      AppRoute.editorialArticle => AppTopBar.back(
        onPressed: onBack,
        actions: <Widget>[
          if (editorialSave case final save?)
            ListenableBuilder(
              listenable: save,
              builder: (context, _) => AppTopBarMaterialAction(
                key: const ValueKey<String>('editorial-article-save'),
                icon: save.saved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: save.saved
                    ? AppColors.actionPrimary
                    : AppColors.textPrimary,
                onPressed: save.saving ? () {} : () => onEditorialSave(save),
                tooltip: save.saved ? '저장 해제' : '게시글 저장',
              ),
            ),
          if (onEditorialInstagram != null)
            AppIconButton(
              key: const ValueKey<String>('editorial-article-instagram'),
              icon: AppIconAsset.instagram,
              onPressed: onEditorialInstagram,
              tooltip: '인스타그램에서 보기',
              tone: AppIconButtonTone.ink,
            ),
        ],
      ),
      AppRoute.savedCards => AppTopBar.back(
        onPressed: onBack,
        title: '저장한 술결 카드',
      ),
      AppRoute.savedArticles => AppTopBar.back(
        onPressed: onBack,
        title: '저장한 게시글',
      ),
      AppRoute.tasteFitDetail => AppTopBar.back(onPressed: onBack),
    };
  }
}
