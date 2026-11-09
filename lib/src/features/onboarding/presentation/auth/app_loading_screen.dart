import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_brand_logo.dart';

/// The app's first frame while the saved session is being checked.
///
/// The logo fades in while drifting up a little; the sub copy follows
/// 200ms later so the two read as one staggered motion.
class AppLoadingScreen extends StatefulWidget {
  const AppLoadingScreen({super.key});

  static const subCopy = '나만의 잔을 찾는 여정';

  @override
  State<AppLoadingScreen> createState() => _AppLoadingScreenState();
}

class _AppLoadingScreenState extends State<AppLoadingScreen>
    with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 800);
  static const _stagger = 0.25; // 200ms of 800ms
  static const _rise = 10.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
  )..forward();

  late final Animation<double> _logo = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 1 - _stagger, curve: Curves.easeOut),
  );
  late final Animation<double> _copy = CurvedAnimation(
    parent: _controller,
    curve: const Interval(_stagger, 1, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey<String>('app-loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FadeRise(
            progress: _logo,
            rise: _rise,
            child: const AppBrandLogo(size: AppBrandLogoSize.large),
          ),
          const SizedBox(height: 18),
          _FadeRise(
            progress: _copy,
            rise: _rise,
            child: const Text(
              AppLoadingScreen.subCopy,
              style: AppTextStyle(
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
                color: AppColors.textWarmSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FadeRise extends StatelessWidget {
  const _FadeRise({
    required this.progress,
    required this.rise,
    required this.child,
  });

  final Animation<double> progress;
  final double rise;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) => Opacity(
        opacity: progress.value,
        child: Transform.translate(
          offset: Offset(0, rise * (1 - progress.value)),
          child: child,
        ),
      ),
    );
  }
}
