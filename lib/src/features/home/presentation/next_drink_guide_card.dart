import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';

import '../../../core/async_shown.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_page_indicator.dart';
import '../../../widgets/app_surface.dart';
import '../../taste_card/presentation/widgets/taste_card_guide_body.dart';
import '../data/home_providers.dart';
import '../data/next_drink_guides.dart';

/// 다음 한 잔 가이드: one slide per recent card that wrote a guide: 내 취향에
/// 맞춘 레드 와인, then the card's guide body as the card draws it (the
/// direction chips, the picks, the marks), without the head sentence and
/// the tip.
/// Tapping a slide opens that card. Without a gateway there is nothing to
/// show, as before the first card.
class NextDrinkGuideCard extends ConsumerWidget {
  const NextDrinkGuideCard({required this.onOpenCard, super.key});

  final ValueChanged<String> onOpenCard;

  static const title = '다음 한 잔 가이드';
  static const emptyMessage = '술결이 쌓이면 다음 술을 고를 기준이 여기 보여요.';
  static const loadingMessage = '불러오는 중이에요.';
  static const failureMessage = '가이드를 불러오지 못했어요.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(nextDrinkGuidesGatewayProvider) == null) {
      return const _NextDrinkGuideMessage(NextDrinkGuideCard.emptyMessage);
    }
    final guides = ref.watch(nextDrinkGuidesProvider);
    final loaded = shownValue(guides);
    if (loaded == null) {
      return _NextDrinkGuideMessage(
        guides.hasError && !guides.isLoading
            ? NextDrinkGuideCard.failureMessage
            : NextDrinkGuideCard.loadingMessage,
      );
    }
    if (loaded.isEmpty) {
      return const _NextDrinkGuideMessage(NextDrinkGuideCard.emptyMessage);
    }
    return _NextDrinkGuideCarousel(guides: loaded, onOpenCard: onOpenCard);
  }
}

class _NextDrinkGuideMessage extends StatelessWidget {
  const _NextDrinkGuideMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => AppPanel(
    padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 18, AppSpacing.xl, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(NextDrinkGuideCard.title, style: AppTextStyles.sectionTitle),
        const SizedBox(height: 17),
        Text(message, style: AppTextStyles.homeCardSupporting),
      ],
    ),
  );
}

class _NextDrinkGuideCarousel extends StatefulWidget {
  const _NextDrinkGuideCarousel({
    required this.guides,
    required this.onOpenCard,
  });

  final List<NextDrinkGuide> guides;
  final ValueChanged<String> onOpenCard;

  @override
  State<_NextDrinkGuideCarousel> createState() =>
      _NextDrinkGuideCarouselState();
}

class _NextDrinkGuideCarouselState extends State<_NextDrinkGuideCarousel> {
  /// The gap between two slides while paging.
  static const _slideGap = 20.0;

  /// Content end to the dots, the same on every slide (the slide's own 4
  /// trailing pixels included).
  static const _indicatorGap = 16.0;

  final _pageController = PageController();
  var _activeIndex = 0;

  /// The slide whose height the pager takes. It moves only when a swipe is
  /// let go, so the panel does not resize under the finger.
  var _heightIndex = 0;
  var _dragging = false;
  final _heights = <int, double>{};

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _setHeight(int index, double height) {
    if (!mounted || _heights[index] == height) return;
    setState(() => _heights[index] = height);
  }

  /// On let-go the pager springs to the page it is moving toward; it takes
  /// that page's height right then.
  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _dragging = true;
    } else if (notification is ScrollUpdateNotification &&
        _dragging &&
        notification.dragDetails == null) {
      _dragging = false;
      final page = _pageController.page ?? _heightIndex.toDouble();
      final delta = notification.scrollDelta ?? 0;
      final target = delta > 0
          ? page.ceil()
          : delta < 0
          ? page.floor()
          : page.round();
      _settleHeight(target);
    } else if (notification is ScrollEndNotification) {
      _dragging = false;
      _settleHeight((_pageController.page ?? 0).round());
    }
    return false;
  }

  void _settleHeight(int index) {
    final target = index.clamp(0, widget.guides.length - 1);
    if (target != _heightIndex) setState(() => _heightIndex = target);
  }

  @override
  Widget build(BuildContext context) {
    final guides = widget.guides;
    final height = _heights[_heightIndex];
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 18, AppSpacing.xl, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  NextDrinkGuideCard.title,
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              Text(
                '${_activeIndex + 1} / ${guides.length}',
                style: AppTextStyles.homeSuggestionPosition,
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Offstage copies report each slide's height at the slide width.
          Offstage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final (index, guide) in guides.indexed)
                  _HeightReporter(
                    onHeight: (height) => _setHeight(index, height),
                    child: _NextDrinkGuideSlide(guide: guide),
                  ),
              ],
            ),
          ),
          if (height != null)
            SizedBox(
              height: height,
              // The pages reach half a gap into the panel's padding on each
              // side and each keeps half a gap clear, so a slide lines up
              // with the title and two slides part by the whole gap.
              child: LayoutBuilder(
                builder: (context, constraints) => OverflowBox(
                  minWidth: constraints.maxWidth + _slideGap,
                  maxWidth: constraints.maxWidth + _slideGap,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: PageView.builder(
                      key: const Key('next-drink-carousel'),
                      controller: _pageController,
                      itemCount: guides.length,
                      onPageChanged: (index) =>
                          setState(() => _activeIndex = index),
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _slideGap / 2,
                        ),
                        child: InkWell(
                          key: ValueKey<String>(
                            'next-drink-guide:${guides[index].resultId}',
                          ),
                          borderRadius: BorderRadius.circular(AppRadii.control),
                          onTap: () =>
                              widget.onOpenCard(guides[index].resultId),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: _NextDrinkGuideSlide(guide: guides[index]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (guides.length > 1) ...<Widget>[
            const SizedBox(height: _indicatorGap),
            Align(
              alignment: Alignment.center,
              child: AppPageIndicator(
                count: guides.length,
                activeIndex: _activeIndex,
                dotSpacing: AppSpacing.xxs,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Calls [onHeight] after layout whenever its child's height changes.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

/// 내 취향에 맞춘 레드 와인, then the guide body with the direction chips
/// right under that title.
class _NextDrinkGuideSlide extends StatelessWidget {
  const _NextDrinkGuideSlide({required this.guide});

  final NextDrinkGuide guide;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(
        '내 취향에 맞춘 ${guide.kindLabel}',
        style: AppTextStyles.homeSuggestionTitle,
      ),
      TasteCardGuideBody(
        guide: guide.guide,
        categoryLabel: guide.categoryLabel,
        directionsLabel: null,
        labelStyle: AppTextStyles.homeSuggestionTitle,
        showTip: false,
      ),
      const SizedBox(height: 4),
    ],
  );
}
