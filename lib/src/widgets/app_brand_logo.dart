import 'package:flutter/widgets.dart';

/// How tall the wordmark is drawn: [medium] in a header's middle and at the
/// top of the home, about as tall as a main tab's name; [large] alone on
/// the loading screen.
enum AppBrandLogoSize { medium, large }

/// The 술결 wordmark. It is the app's mark where it stands, not a way
/// home, so it is read as 술결 only.
class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({super.key, this.size = AppBrandLogoSize.medium});

  /// A wide picture (623×160), sized by its height.
  static const assetPath = 'assets/brand/soolgyul_wordmark.webp';

  final AppBrandLogoSize size;

  double get height => switch (size) {
    AppBrandLogoSize.medium => 24,
    AppBrandLogoSize.large => 40,
  };

  @override
  Widget build(BuildContext context) => Image.asset(
    assetPath,
    height: height,
    filterQuality: FilterQuality.medium,
    semanticLabel: '술결',
  );
}
