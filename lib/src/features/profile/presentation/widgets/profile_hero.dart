import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_icon_button.dart';
import '../../../../widgets/edge_fade.dart';

class ProfileHero extends StatelessWidget {
  const ProfileHero({
    super.key,
    required this.nickname,
    required this.onEditNickname,
  });

  final String nickname;
  final VoidCallback onEditNickname;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final extraTextHeight = 44 * (textScale - 1).clamp(0.0, 1.0);

    return SizedBox(
      height: 242 + extraTextHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 154,
            child: EdgeFade(
              bottom: .4,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.asset(
                    'assets/images/profile/profile_hero_wine.png',
                    key: const ValueKey<String>('profile-hero-background'),
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                  ColoredBox(color: AppColors.scrim.withValues(alpha: .08)),
                ],
              ),
            ),
          ),
          Positioned(
            top: 158,
            left: AppSpacing.screenX,
            right: AppSpacing.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.profileName,
                      ),
                    ),
                    AppIconButton(
                      key: const ValueKey<String>('profile-nickname-edit'),
                      icon: AppIconAsset.edit,
                      onPressed: onEditNickname,
                      tooltip: '닉네임 수정',
                      size: AppIconButtonSize.compact,
                      tone: AppIconButtonTone.neutral,
                    ),
                  ],
                ),
                // The pencil's tap target already pads the name row.
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '한 잔씩, 나만의 결을 찾아가는 중',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
