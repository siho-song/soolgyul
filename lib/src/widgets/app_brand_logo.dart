import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum AppBrandLogoSize { medium, large }

class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({super.key, this.size = AppBrandLogoSize.medium});

  static const assetPath = 'assets/brand/soolgyeol_logo.svg';
  static const aspectRatio = 890 / 638;

  final AppBrandLogoSize size;

  double get width => switch (size) {
    AppBrandLogoSize.medium => 40,
    AppBrandLogoSize.large => 96,
  };

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      assetPath,
      width: width,
      height: width / aspectRatio,
      fit: BoxFit.contain,
      semanticsLabel: '술결 홈으로 이동',
    );
  }
}
