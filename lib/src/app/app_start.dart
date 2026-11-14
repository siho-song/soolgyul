import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/errors/error_report.dart';
import '../design/app_theme.dart';
import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import '../widgets/app_button.dart';

/// Gets the app ready and then shows it. Whatever [start] needs (the server
/// client, the phone's secure storage, a login SDK) can fail or be refused
/// on a given phone; the member is then told and can try again, where the
/// launch screen used to stay for good.
class AppStart extends StatefulWidget {
  const AppStart({required this.start, super.key});

  /// Prepares everything and gives the app. Runs again on a retry, so each
  /// step must stand being run twice.
  final Future<Widget> Function() start;

  @override
  State<AppStart> createState() => _AppStartState();
}

class _AppStartState extends State<AppStart> {
  Widget? _app;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final app = await widget.start();
      if (mounted) setState(() => _app = app);
    } catch (error, stack) {
      reportError(error, stack, where: 'start');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _retry() {
    setState(() => _failed = false);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: appStatusBarStyle,
      child: _app ?? _startScreen(),
    );
  }

  Widget _startScreen() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: fixedTextScale,
      home: Scaffold(
        body: _failed
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '앱을 시작하지 못했어요',
                        style: AppTextStyles.sectionTitle,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '네트워크 연결을 확인한 뒤 다시 시도해 주세요.',
                        style: AppTextStyles.body,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppButton(
                        key: const ValueKey<String>('app-start-retry'),
                        label: '다시 시도',
                        onPressed: _retry,
                      ),
                    ],
                  ),
                ),
              )
            // The app's own loading screen follows within a moment.
            : const SizedBox.expand(),
      ),
    );
  }
}

/// What stands in for a part of a screen that could not be drawn. A debug
/// run keeps Flutter's red box, which says what went wrong.
Widget brokenView(FlutterErrorDetails details) => const ColoredBox(
  color: AppColors.surfaceCanvas,
  child: Center(
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '화면을 표시하지 못했어요.\n앱을 다시 실행해 주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 15,
            height: 1.5,
            decoration: TextDecoration.none,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    ),
  ),
);
