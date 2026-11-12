import 'package:flutter/material.dart';

import '../../../core/errors/error_report.dart';
import '../../../core/open_link.dart';
import '../../../design/app_theme.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../data/app_gate.dart';

/// Stands between a member and the app when the server says this version is
/// too old for it, or that the service is paused.
///
/// The gate is asked when the app starts and each time it comes back to the
/// front. The app shows meanwhile, and stays when the answer cannot be had:
/// a phone without a network is not kept out by a question it cannot ask.
class AppGateView extends StatefulWidget {
  const AppGateView({
    required this.load,
    required this.installedVersion,
    required this.storeAddress,
    required this.child,
    super.key,
  });

  final Future<AppGate?> Function() load;

  /// Null where no version can be too old.
  final String? installedVersion;

  /// Where the update is; null hides the button.
  final String? storeAddress;

  final Widget child;

  @override
  State<AppGateView> createState() => _AppGateViewState();
}

class _AppGateViewState extends State<AppGateView> {
  AppGate _gate = const AppGate();
  bool _asking = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _ask);
    _ask();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    if (_asking) return;
    setState(() => _asking = true);
    try {
      final gate = await widget.load();
      if (mounted) setState(() => _gate = gate ?? const AppGate());
    } catch (error, stack) {
      // What was known before stands.
      reportError(error, stack, where: 'gate');
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _openStore() async {
    final address = widget.storeAddress;
    if (address != null) await openLink(address);
  }

  @override
  Widget build(BuildContext context) {
    final decision = _gate.decide(widget.installedVersion);
    if (decision == AppGateDecision.open) return widget.child;
    final updating = decision == AppGateDecision.updateRequired;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: fixedTextScale,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                key: ValueKey<String>(
                  updating ? 'app-gate-update' : 'app-gate-maintenance',
                ),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    updating ? '업데이트가 필요해요' : '잠시 점검 중이에요',
                    style: AppTextStyles.sectionTitle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    updating
                        ? '지금 버전은 더 이상 사용할 수 없어요.\n새 버전으로 업데이트해 주세요.'
                        : _gate.maintenanceMessage!,
                    style: AppTextStyles.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (!updating)
                    AppButton(
                      key: const ValueKey<String>('app-gate-ask-again'),
                      label: '다시 확인',
                      onPressed: _asking ? null : _ask,
                    )
                  else if (widget.storeAddress != null)
                    AppButton(
                      key: const ValueKey<String>('app-gate-open-store'),
                      label: '업데이트하기',
                      onPressed: _openStore,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
