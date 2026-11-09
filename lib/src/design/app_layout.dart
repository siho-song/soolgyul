import 'package:flutter/widgets.dart';

class AppLayout {
  const AppLayout._();

  static const iPhone17Viewport = Size(402, 874);
  static const iPhone17SafeArea = EdgeInsets.only(top: 62, bottom: 34);
  static const compactPhoneWidth = 380.0;
  static const regularPhoneWidth = 430.0;
  static const tallPhoneRatio = 2.05;
  static const headerHorizontalPadding = 14.0;
  static const contentHorizontalPadding = 22.0;

  static bool isViewportReady(BoxConstraints constraints) {
    return constraints.maxWidth >= 120 && constraints.maxHeight >= 120;
  }

  static bool isTallPhone(Size screenSize) {
    return screenSize.height / screenSize.width > tallPhoneRatio;
  }

  static double screenHorizontalPadding(double screenWidth) {
    return contentHorizontalPadding;
  }
}

class AppScreenLayout {
  const AppScreenLayout({
    required this.screenWidth,
    required this.screenHeight,
    required this.horizontalPadding,
    required this.availableContentWidth,
    required this.isTallPhone,
  });

  final double screenWidth;
  final double screenHeight;
  final double horizontalPadding;
  final double availableContentWidth;
  final bool isTallPhone;

  factory AppScreenLayout.fromConstraints(BoxConstraints constraints) {
    final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
    final horizontalPadding = AppLayout.screenHorizontalPadding(
      screenSize.width,
    );

    return AppScreenLayout(
      screenWidth: screenSize.width,
      screenHeight: screenSize.height,
      horizontalPadding: horizontalPadding,
      availableContentWidth: screenSize.width - horizontalPadding * 2,
      isTallPhone: AppLayout.isTallPhone(screenSize),
    );
  }

  double scaledHeight({
    required double ratio,
    required double minimum,
    required double maximum,
  }) {
    return (screenHeight * ratio).clamp(minimum, maximum);
  }
}
