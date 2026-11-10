import 'package:flutter/material.dart';
import '../../../../widgets/app_switch.dart';
import '../../data/marketing_consent_gateway.dart';

class MarketingConsentControl extends StatefulWidget {
  const MarketingConsentControl({
    this.gateway,
    this.isActive = true,
    super.key,
  });
  final MarketingConsentGateway? gateway;
  final bool isActive;
  @override
  State<MarketingConsentControl> createState() =>
      _MarketingConsentControlState();
}

class _MarketingConsentControlState extends State<MarketingConsentControl> {
  bool? _accepted;
  bool _busy = false;
  bool _failed = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    if (widget.isActive) _load();
  }

  @override
  void didUpdateWidget(MarketingConsentControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gateway != oldWidget.gateway ||
        widget.isActive != oldWidget.isActive) {
      _request++;
      _accepted = null;
      _busy = false;
      if (widget.isActive) _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final gateway = widget.gateway;
      if (gateway == null) throw StateError('unavailable');
      final value = await gateway.load();
      if (mounted && request == _request) setState(() => _accepted = value);
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _save(bool value) async {
    if (_busy || widget.gateway == null) return;
    final request = ++_request;
    setState(() => _busy = true);
    try {
      final saved = await widget.gateway!.save(value);
      if (saved != value) throw StateError('unexpected_consent');
      if (mounted && request == _request) setState(() => _accepted = saved);
    } catch (_) {
      if (mounted && request == _request) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return TextButton(onPressed: _load, child: const Text('다시 시도'));
    }
    if (_accepted == null) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return AppSwitch(
      key: const ValueKey<String>('policy-marketing-consent'),
      value: _accepted!,
      onChanged: _busy || !widget.isActive ? null : _save,
      semanticLabel: '마케팅 정보 수신 동의',
    );
  }
}
