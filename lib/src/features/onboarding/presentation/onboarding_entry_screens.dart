import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/app_layout.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_page_indicator.dart';

/// One slide of the first onboarding page: two lines over a phone showing
/// the app's own screen.
@immutable
class OnboardingPreviewSlide {
  const OnboardingPreviewSlide({
    required this.lead,
    required this.title,
    required this.asset,
  });

  final String lead;
  final String title;
  final String asset;
}

/// The first onboarding page: what the app gives, shown on its own screens
/// slide by slide, and the start button under every slide, so the visitor
/// can start without swiping through. The slides move on by themselves;
/// a touch starts the wait again.
class OnboardingWelcomeScreen extends StatefulWidget {
  const OnboardingWelcomeScreen({required this.onStart, super.key});

  final VoidCallback onStart;

  static const slides = <OnboardingPreviewSlide>[
    OnboardingPreviewSlide(
      lead: '마신 술 한 잔만 기록하면',
      title: '내 취향 분석부터 다음 술 가이드까지',
      asset: 'assets/images/onboarding/onboarding_preview_card.webp',
    ),
    OnboardingPreviewSlide(
      lead: '취향 데이터가 쌓이면',
      title: '라벨만 찍어도 내 입맛인지 바로 확인',
      asset: 'assets/images/onboarding/onboarding_preview_fit.webp',
    ),
    OnboardingPreviewSlide(
      lead: '어려운 술 용어, 검색할 필요 없이',
      title: '모르는 단어만 톡 눌러서 확인',
      asset: 'assets/images/onboarding/onboarding_preview_term.webp',
    ),
    OnboardingPreviewSlide(
      lead: '기록이 쌓일수록',
      title: '나만의 취향 카드 완성',
      asset: 'assets/images/onboarding/onboarding_preview_taste.webp',
    ),
  ];

  /// Below this the page scrolls instead of shrinking the phone further.
  static const minimumHeight = 520.0;

  /// How long a slide stays before the next one comes by itself.
  static const slideInterval = Duration(seconds: 4);

  @override
  State<OnboardingWelcomeScreen> createState() =>
      _OnboardingWelcomeScreenState();
}

class _OnboardingWelcomeScreenState extends State<OnboardingWelcomeScreen> {
  final _pageController = PageController();
  Timer? _nextSlide;
  var _page = 0;

  @override
  void initState() {
    super.initState();
    _waitForNextSlide();
  }

  @override
  void dispose() {
    _nextSlide?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _waitForNextSlide() {
    _nextSlide?.cancel();
    _nextSlide = Timer.periodic(
      OnboardingWelcomeScreen.slideInterval,
      (_) => _showNextSlide(),
    );
  }

  /// After the last slide the first comes again. With reduced motion the
  /// slide changes without sliding.
  void _showNextSlide() {
    if (!mounted || !_pageController.hasClients) return;
    final next = (_page + 1) % OnboardingWelcomeScreen.slides.length;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(next);
    } else {
      _pageController.animateToPage(
        next,
        duration: AppDurations.slow,
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const slides = OnboardingWelcomeScreen.slides;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!AppLayout.isViewportReady(constraints)) {
          return const SizedBox.shrink();
        }
        final layout = AppScreenLayout.fromConstraints(constraints);
        final padding = layout.horizontalPadding;
        return SingleChildScrollView(
          key: const ValueKey<String>('onboarding-page-scroll'),
          child: SizedBox(
            height: math.max(
              constraints.maxHeight,
              OnboardingWelcomeScreen.minimumHeight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: AppSpacing.lg),
                AppPageIndicator(count: slides.length, activeIndex: _page),
                const SizedBox(height: AppSpacing.xl),
                Expanded(
                  child: Listener(
                    onPointerDown: (_) => _waitForNextSlide(),
                    child: PageView.builder(
                      key: const ValueKey<String>('onboarding-welcome-slides'),
                      controller: _pageController,
                      itemCount: slides.length,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, index) => Padding(
                        padding: EdgeInsets.symmetric(horizontal: padding),
                        child: _PreviewSlide(slide: slides[index]),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    AppSpacing.lg,
                    padding,
                    AppSpacing.xxl,
                  ),
                  child: AppButton(
                    key: const ValueKey<String>('onboarding-welcome-start'),
                    label: '시작하기',
                    size: AppButtonSize.prominent,
                    onPressed: widget.onStart,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The two lines, each kept on one line and shrunk to fit, then the phone
/// filling the room left, top-aligned so its faded foot sits on the button.
class _PreviewSlide extends StatelessWidget {
  const _PreviewSlide({required this.slide});

  final OnboardingPreviewSlide slide;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(slide.lead, style: AppTextStyles.onboardingBody),
      ),
      const SizedBox(height: AppSpacing.xs),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(slide.title, style: AppTextStyles.onboardingTitle),
      ),
      const SizedBox(height: AppSpacing.xxl),
      Expanded(
        child: Image.asset(
          slide.asset,
          key: ValueKey<String>('onboarding-welcome-image:${slide.asset}'),
          fit: BoxFit.contain,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
      ),
    ],
  );
}
