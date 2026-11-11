import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/app_snack_bar.dart';
import '../../../../widgets/app_state_view.dart';
import '../../../../widgets/app_switch.dart';
import '../../data/notification_access.dart';
import '../../data/notification_prompt_memory.dart';

/// The settings row that turns the app's notifications on and off. When the
/// phone's settings refuse them it offers the way there instead, and reads
/// the state again when the member comes back to the app.
class NotificationSettingRow extends StatefulWidget {
  const NotificationSettingRow({
    required this.access,
    this.memory,
    this.isActive = true,
    super.key,
  });

  final NotificationAccess access;
  final NotificationPromptMemory? memory;
  final bool isActive;

  @override
  State<NotificationSettingRow> createState() => _NotificationSettingRowState();
}

class _NotificationSettingRowState extends State<NotificationSettingRow>
    with WidgetsBindingObserver {
  NotificationStatus? _status;
  bool _busy = false;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) _load();
  }

  @override
  void didUpdateWidget(NotificationSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.access != oldWidget.access ||
        widget.isActive != oldWidget.isActive) {
      _status = null;
      if (widget.isActive) _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isActive) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _run(
    Future<NotificationStatus> Function() action, {
    required bool isLoad,
  }) async {
    final request = ++_request;
    setState(() {
      _busy = true;
      if (isLoad) _failed = false;
    });
    try {
      final status = await action();
      if (mounted && request == _request) setState(() => _status = status);
    } catch (_) {
      if (!mounted || request != _request) return;
      if (isLoad) {
        setState(() => _failed = true);
      } else {
        showAppSnackBar(context, '설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(widget.access.load, isLoad: true);

  Future<void> _toggle(bool on) => _run(() async {
    if (on) return widget.access.turnOn();
    final status = await widget.access.turnOff();
    await widget.memory?.rememberTurnedOff();
    return status;
  }, isLoad: false);

  Widget _control() {
    if (_failed) return AppRetryButton(onPressed: _load);
    return switch (_status) {
      null => const AppSmallSpinner(),
      NotificationStatus.blocked => AppButton(
        key: const ValueKey<String>('notification-open-settings'),
        label: '설정 열기',
        size: AppButtonSize.compact,
        variant: AppButtonVariant.secondary,
        widthMode: AppButtonWidthMode.intrinsic,
        onPressed: widget.access.openPhoneSettings,
      ),
      final status => AppSwitch(
        key: const ValueKey<String>('notification-switch'),
        value: status == NotificationStatus.on,
        onChanged: _busy || !widget.isActive ? null : _toggle,
        semanticLabel: '알림 받기',
      ),
    };
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: AppSizes.menuRowHeight),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('알림 받기', style: AppTextStyles.menuItemTitle),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _status == NotificationStatus.blocked
                      ? '폰 설정에서 술결 알림이 꺼져 있어요'
                      : '술 고르기 좋은 때에 알려 드려요',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _control(),
        ],
      ),
    ),
  );
}
