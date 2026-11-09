import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design/app_feature_layouts.dart';
import '../../../design/app_layout.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../data/profile_summary_provider.dart';
import '../data/profile_setup_draft.dart';
import 'drink_interest_sheet.dart';
import 'nickname_edit_sheet.dart';
import 'profile_destination.dart';
import 'widgets/profile_hero.dart';
import 'widgets/profile_menu_panel.dart';
import 'widgets/profile_record_cards.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({
    required this.onNavigate,
    required this.onSaveNickname,
    required this.onSaveInterests,
    this.nickname = '민지',
    this.interests = const <DrinkInterest>{
      DrinkInterest.wine,
      DrinkInterest.whisky,
      DrinkInterest.koreanTraditional,
      DrinkInterest.sake,
    },
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
        return AppPageScrollView(
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
                      TextButton(
                        onPressed: ref
                            .read(profileSummaryProvider.notifier)
                            .refresh,
                        child: const Text('내 기록을 불러오지 못했어요. 다시 시도'),
                      ),
                    const SizedBox(height: ProfileLayoutSpacing.sectionGap),
                    Text('내 보관함', style: AppTextStyles.sectionTitle),
                    const SizedBox(
                      height: ProfileLayoutSpacing.sectionToContent,
                    ),
                    ProfileMenuPanel(
                      items: <ProfileMenuItem>[
                        ProfileMenuItem(
                          materialIcon: Icons.article_outlined,
                          title: '저장한 게시글',
                          count: summary?.savedArticleCount.toString() ?? '—',
                          onPressed: () => widget.onNavigate(
                            ProfileDestination.savedArticles,
                          ),
                        ),
                        ProfileMenuItem(
                          materialIcon: Icons.favorite_border_rounded,
                          title: '저장한 술결 카드',
                          count: summary?.likedCardCount.toString() ?? '—',
                          onPressed: () =>
                              widget.onNavigate(ProfileDestination.savedCards),
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
                          title: '약관 및 개인정보',
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
                          title: '도움말 및 문의',
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
      },
    );
  }
}
