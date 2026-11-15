import '../../../design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design/app_feature_layouts.dart';
import '../../../design/app_layout.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../../../core/async_shown.dart';
import '../../glossary/data/saved_terms_provider.dart';
import '../data/profile_summary_provider.dart';
import '../data/profile_setup_draft.dart';
import 'drink_interest_sheet.dart';
import 'nickname_edit_sheet.dart';
import 'profile_destination.dart';
import 'widgets/profile_hero.dart';
import 'widgets/profile_menu_panel.dart';
import 'widgets/profile_record_cards.dart';
import '../../../widgets/app_state_view.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({
    required this.onNavigate,
    required this.onSaveNickname,
    required this.onSaveInterests,
    required this.nickname,
    required this.interests,
    super.key,
  });

  final ValueChanged<ProfileDestination> onNavigate;
  final NicknameSaver onSaveNickname;
  final DrinkInterestSaver onSaveInterests;
  final String nickname;
  final Set<DrinkInterest> interests;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// How far the page has scrolled. The picture at its top reaches under
  /// the status bar; once the page moves, a strip in the page's colour
  /// comes over that bar so the clock is not read through the content.
  final ValueNotifier<double> _scrolled = ValueNotifier<double>(0);

  @override
  void dispose() {
    _scrolled.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // The counts load after sign-in; this covers an entry that skipped it.
    // A provider may not change while the tree builds, so it asks right
    // after this frame's build.
    Future.microtask(() {
      if (mounted && ref.read(profileSummaryProvider).needsLoad) {
        ref.read(profileSummaryProvider.notifier).refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!AppLayout.isViewportReady(constraints)) {
          return const SizedBox.shrink();
        }
        final layout = AppScreenLayout.fromConstraints(constraints);
        final counts = ref.watch(profileSummaryProvider);
        final summary = counts.summary;
        final failed = counts.failed;
        final statusBar = MediaQuery.viewPaddingOf(context).top;
        final page = AppPageScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ProfileHero(
                nickname: widget.nickname,
                onEditNickname: () => showNicknameEditSheet(
                  context,
                  initialNickname: widget.nickname,
                  onSave: widget.onSaveNickname,
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.horizontalPadding,
                  ProfileLayoutSpacing.heroToContent,
                  layout.horizontalPadding,
                  ProfileLayoutSpacing.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ProfileInterestsCard(
                      labels: widget.interests,
                      onPressed: () => showDrinkInterestSheet(
                        context,
                        initialSelection: widget.interests,
                        onSave: widget.onSaveInterests,
                      ),
                    ),
                    if (failed && summary == null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.lg),
                        child: AppCardError(
                          message: '기록을 불러오지 못했어요.',
                          onRetry: ref
                              .read(profileSummaryProvider.notifier)
                              .refresh,
                        ),
                      ),
                    const SizedBox(height: ProfileLayoutSpacing.sectionGap),
                    Text('내 서랍', style: AppTextStyles.sectionTitle),
                    const SizedBox(
                      height: ProfileLayoutSpacing.sectionToContent,
                    ),
                    ProfileMenuPanel(
                      items: <ProfileMenuItem>[
                        ProfileMenuItem(
                          materialIcon: Icons.article_outlined,
                          title: '저장한 이야기',
                          count: summary?.savedArticleCount.toString() ?? '—',
                          onPressed: () => widget.onNavigate(
                            ProfileDestination.savedArticles,
                          ),
                        ),
                        ProfileMenuItem(
                          materialIcon: Icons.favorite_border_rounded,
                          title: '보관한 술결 카드',
                          count: summary?.likedCardCount.toString() ?? '—',
                          onPressed: () =>
                              widget.onNavigate(ProfileDestination.savedCards),
                        ),
                        ProfileMenuItem(
                          materialIcon: Icons.liquor_outlined,
                          title: '저장한 술',
                          count: summary?.savedDrinkCount.toString() ?? '—',
                          onPressed: () =>
                              widget.onNavigate(ProfileDestination.savedDrinks),
                        ),
                        ProfileMenuItem(
                          materialIcon: Icons.menu_book_outlined,
                          title: '나의 용어 사전',
                          count:
                              shownValue(
                                ref.watch(savedTermsProvider),
                              )?.length.toString() ??
                              '—',
                          onPressed: () =>
                              widget.onNavigate(ProfileDestination.savedTerms),
                        ),
                      ],
                    ),
                    const SizedBox(height: ProfileLayoutSpacing.sectionGap),
                    Text('설정 및 지원', style: AppTextStyles.sectionTitle),
                    const SizedBox(
                      height: ProfileLayoutSpacing.sectionToContent,
                    ),
                    ProfileMenuPanel(
                      items: <ProfileMenuItem>[
                        ProfileMenuItem(
                          materialIcon: Icons.lock_outline_rounded,
                          title: '약관 및 정책',
                          onPressed: () =>
                              widget.onNavigate(ProfileDestination.policy),
                        ),
                        ProfileMenuItem(
                          materialIcon: Icons.campaign_outlined,
                          title: '공지사항',
                          onPressed: () =>
                              widget.onNavigate(ProfileDestination.notice),
                        ),
                        ProfileMenuItem(
                          materialIcon: Icons.help_outline_rounded,
                          title: '고객지원 및 문의',
                          onPressed: () => widget.onNavigate(
                            ProfileDestination.supportCenter,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        return Stack(
          children: <Widget>[
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis == Axis.vertical &&
                    notification.depth == 0) {
                  _scrolled.value = notification.metrics.pixels;
                }
                return false;
              },
              child: page,
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: statusBar,
              child: IgnorePointer(
                child: ValueListenableBuilder<double>(
                  valueListenable: _scrolled,
                  builder: (context, scrolled, strip) => Opacity(
                    opacity: (scrolled / AppSpacing.xl).clamp(0, 1).toDouble(),
                    child: strip,
                  ),
                  child: const ColoredBox(
                    key: ValueKey<String>('profile-status-bar-cover'),
                    color: AppColors.surfaceCanvas,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
