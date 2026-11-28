import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/edge_fade.dart';

/// The top of the 내 정보 tab, which has no header bar and no title: the
/// picture across the page, reaching under the status bar and fading into
/// the page, then whose page it is: the nickname, and under it the
/// account's email. An account without an email has no such line. The
/// nickname is changed from the 계정 rows below.
class ProfileHero extends StatelessWidget {
  const ProfileHero({super.key, required this.nickname, this.email});

  final String nickname;

  /// The signed-in account's email; null for an account without one.
  final String? email;

  static const _pictureHeight = 154.0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      SizedBox(
        height: _pictureHeight,
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
                excludeFromSemantics: true,
              ),
              ColoredBox(color: AppColors.scrim.withValues(alpha: .08)),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenX,
          AppSpacing.xs,
          AppSpacing.screenX,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Until the profile is read there is no name, and no line for it.
            if (nickname.isNotEmpty)
              Text(
                nickname,
                key: const ValueKey<String>('profile-nickname'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.profileName,
              ),
            if (email case final email?) ...<Widget>[
              if (nickname.isNotEmpty) const SizedBox(height: AppSpacing.xs),
              Text(
                email,
                key: const ValueKey<String>('profile-email'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMuted,
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
