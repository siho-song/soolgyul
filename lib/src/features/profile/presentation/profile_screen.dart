import 'package:flutter/material.dart';
import '../../../design/app_feature_layouts.dart';
import '../../../design/app_layout.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../data/profile_summary_store.dart';
import '../profile_setup_draft.dart';
import 'drink_interest_sheet.dart';
import 'nickname_edit_sheet.dart';
import 'profile_destination.dart';
import 'widgets/profile_hero.dart';
import 'widgets/profile_menu_panel.dart';
import 'widgets/profile_record_cards.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.onNavigate,
    required this.onSaveNickname,
    required this.onSaveInterests,
    this.nickname = '민지',
    this.summaryStore,
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
  final ProfileSummaryStore? summaryStore;
  final Set<DrinkInterest> interests;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    _loadIfMissing();
    widget.summaryStore?.addListener(_onSummary);
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.summaryStore != oldWidget.summaryStore) {
      oldWidget.summaryStore?.removeListener(_onSummary);
      _loadIfMissing();
      widget.summaryStore?.addListener(_onSummary);
    }
  }

  @override
  void dispose() {
    widget.summaryStore?.removeListener(_onSummary);
    super.dispose();
  }

  void _onSummary() => setState(() {});

  /// The counts load after sign-in; this covers an entry that skipped it.
  void _loadIfMissing() {
    final store = widget.summaryStore;
    if (store != null && store.needsLoad) store.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!AppLayout.isViewportReady(constraints)) {
          return const SizedBox.shrink();
        }
        final layout = AppScreenLayout.fromConstraints(constraints);
        final summary = widget.summaryStore?.summary;
        final failed = widget.summaryStore?.failed ?? false;
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
                        onPressed: widget.summaryStore?.refresh,
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
