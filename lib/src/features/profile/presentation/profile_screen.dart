import '../../../core/catalog/drink_type.dart';
import 'package:flutter/material.dart';
import '../../../design/app_feature_layouts.dart';
import '../../../design/app_layout.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_page_scroll_view.dart';
import 'drink_interest_sheet.dart';
import 'nickname_edit_popup.dart';
import 'profile_destination.dart';
import 'widgets/profile_hero.dart';
import 'widgets/profile_menu_list.dart';

/// The 내 정보 tab: its picture and whose page it is, the account's rows
/// (the nickname and the drinks of interest, each changed in its popup or
/// sheet), the drawer of what was saved, and the settings. Everything it shows
/// is already held by the app, so the tab reads nothing when it opens.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.onNavigate,
    required this.onSaveNickname,
    required this.onSaveInterests,
    required this.nickname,
    required this.interests,
    this.email,
    super.key,
  });

  final ValueChanged<ProfileDestination> onNavigate;
  final NicknameSaver onSaveNickname;
  final DrinkInterestSaver onSaveInterests;
  final String nickname;
  final Set<DrinkType> interests;

  /// The signed-in account's email; null for an account without one.
  final String? email;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
  Widget build(BuildContext context) {
    final ProfileScreen(
      :nickname,
      :email,
      :interests,
      :onNavigate,
      :onSaveNickname,
      :onSaveInterests,
    ) = widget;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!AppLayout.isViewportReady(constraints)) {
          return const SizedBox.shrink();
        }
        final layout = AppScreenLayout.fromConstraints(constraints);
        final statusBar = MediaQuery.viewPaddingOf(context).top;
        final page = AppPageScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ProfileHero(nickname: nickname, email: email),
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
                    Text('계정', style: AppTextStyles.sectionTitleSm),
                    const SizedBox(
                      height: ProfileLayoutSpacing.sectionToContent,
                    ),
                    ProfileMenuList(
                      items: <ProfileMenuItem>[
                        ProfileMenuItem(
                          key: const ValueKey<String>('profile-nickname-edit'),
                          icon: ProfileMenuIcon.nickname,
                          title: '닉네임 변경',
                          onPressed: () => showNicknameEditPopup(
                            context,
                            initialNickname: nickname,
                            onSave: onSaveNickname,
                          ),
                        ),
                        ProfileMenuItem(
                          key: const ValueKey<String>(
                            'profile-interest-settings',
                          ),
                          icon: ProfileMenuIcon.interests,
                          title: '관심 주종',
                          onPressed: () => showDrinkInterestSheet(
                            context,
                            initialSelection: interests,
                            onSave: onSaveInterests,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: ProfileLayoutSpacing.sectionGap),
                    Text('내 서랍', style: AppTextStyles.sectionTitleSm),
                    const SizedBox(
                      height: ProfileLayoutSpacing.sectionToContent,
                    ),
                    // A row is its icon, its name and the arrow: what it
                    // holds is seen by opening it.
                    ProfileMenuList(
                      items: <ProfileMenuItem>[
                        ProfileMenuItem(
                          icon: ProfileMenuIcon.savedDrinks,
                          title: '저장한 술',
                          onPressed: () =>
                              onNavigate(ProfileDestination.savedDrinks),
                        ),
                        ProfileMenuItem(
                          icon: ProfileMenuIcon.glossary,
                          title: '나의 용어 사전',
                          onPressed: () =>
                              onNavigate(ProfileDestination.savedTerms),
                        ),
                      ],
                    ),
                    const SizedBox(height: ProfileLayoutSpacing.sectionGap),
                    Text('설정 및 지원', style: AppTextStyles.sectionTitleSm),
                    const SizedBox(
                      height: ProfileLayoutSpacing.sectionToContent,
                    ),
                    ProfileMenuList(
                      items: <ProfileMenuItem>[
                        ProfileMenuItem(
                          icon: ProfileMenuIcon.policy,
                          title: '약관 및 정책',
                          onPressed: () =>
                              onNavigate(ProfileDestination.policy),
                        ),
                        ProfileMenuItem(
                          icon: ProfileMenuIcon.notice,
                          title: '공지사항',
                          onPressed: () =>
                              onNavigate(ProfileDestination.notice),
                        ),
                        ProfileMenuItem(
                          icon: ProfileMenuIcon.inquiry,
                          title: '문의하기',
                          onPressed: () =>
                              onNavigate(ProfileDestination.inquiry),
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
