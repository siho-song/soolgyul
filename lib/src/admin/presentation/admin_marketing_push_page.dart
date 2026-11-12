import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ids.dart';
import '../../design/app_tokens.dart';
import '../../design/app_typography.dart';
import '../admin_editorial_models.dart';
import '../data/admin_editorial_gateway.dart';
import 'admin_widgets.dart';

/// What the server puts around the admin's words in every marketing
/// notification (`supabase/functions/marketing-push/index.ts`), shown here
/// so the admin sees the notification as a member will.
const _advertisementMark = '(광고) ';
const _refusalLine = '수신거부: 마이페이지 > 약관 및 정책';

/// Sends a marketing notification to the members who agreed to marketing
/// and have notifications on: its words, how it will look, whom it reaches
/// now, and the sends so far.
class AdminMarketingPushPage extends StatefulWidget {
  const AdminMarketingPushPage({required this.gateway, super.key});

  final AdminEditorialGateway gateway;

  @override
  State<AdminMarketingPushPage> createState() => _AdminMarketingPushPageState();
}

class _AdminMarketingPushPageState extends State<AdminMarketingPushPage> {
  static const _titleLimit = 30;
  static const _bodyLimit = 100;

  final _title = TextEditingController();
  final _body = TextEditingController();
  AdminMarketingPushOverview? _overview;
  bool _failed = false;
  bool _sending = false;

  /// Names the send being written. It stays the same until a send is known
  /// to have gone out, so a retry after a lost answer is not a second send.
  String _sendId = createUuidV4();

  @override
  void initState() {
    super.initState();
    _title.addListener(_onTyped);
    _body.addListener(_onTyped);
    unawaited(_load());
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _onTyped() => setState(() {});

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final overview = await widget.gateway.loadMarketingPushOverview();
      if (mounted) setState(() => _overview = overview);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String get _titleText => _title.text.trim();

  String get _bodyText => _body.text.trim();

  bool get _canSend =>
      !_sending &&
      _titleText.isNotEmpty &&
      _bodyText.isNotEmpty &&
      (_overview?.deviceCount ?? 0) > 0;

  Future<void> _send() async {
    final devices = _overview?.deviceCount ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('휴대폰 $devices대에 보낼까요?'),
        content: const Text('보낸 알림은 되돌릴 수 없어요.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey<String>('admin-push-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('보내기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _sending) return;
    setState(() => _sending = true);
    try {
      final result = await widget.gateway.sendMarketingPush(
        id: _sendId,
        title: _titleText,
        body: _bodyText,
      );
      if (!mounted) return;
      _startNewSend();
      _showMessage('휴대폰 ${result.deviceCount}대 중 ${result.sentCount}대에 보냈습니다.');
    } on AdminMarketingPushException catch (error) {
      if (!mounted) return;
      switch (error.refusal) {
        case AdminMarketingPushRefusal.nightHours:
          _showMessage('밤 9시부터 아침 8시까지는 보낼 수 없습니다.');
        case AdminMarketingPushRefusal.alreadySent:
          _startNewSend();
          _showMessage('이미 보낸 알림입니다. 보낸 기록을 확인해 주세요.');
        case null:
          _showMessage('보내지 못했습니다. 보낸 기록을 확인한 뒤 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    await _load();
  }

  void _startNewSend() {
    _sendId = createUuidV4();
    _title.clear();
    _body.clear();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      children: <Widget>[
        Text('알림 보내기', style: AppTextStyles.screenTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          overview == null
              ? '마케팅 수신에 동의하고 알림을 켠 회원에게 보내요.'
              : '지금 보내면 회원 ${overview.memberCount}명, '
                    '휴대폰 ${overview.deviceCount}대가 받아요.',
          key: const ValueKey<String>('admin-push-audience'),
          style: AppTextStyles.caption,
        ),
        const SizedBox(height: AppSpacing.xl),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  key: const ValueKey<String>('admin-push-title'),
                  controller: _title,
                  enabled: !_sending,
                  maxLength: _titleLimit,
                  decoration: const InputDecoration(labelText: '제목'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const ValueKey<String>('admin-push-body'),
                  controller: _body,
                  enabled: !_sending,
                  maxLength: _bodyLimit,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '내용',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('회원에게 이렇게 보여요', style: AppTextStyles.caption),
                const SizedBox(height: AppSpacing.xs),
                _Notice(
                  key: const ValueKey<String>('admin-push-preview'),
                  title:
                      '$_advertisementMark'
                      '${_titleText.isEmpty ? '제목' : _titleText}',
                  body:
                      '${_bodyText.isEmpty ? '내용' : _bodyText}\n'
                      '$_refusalLine',
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '밤 9시부터 아침 8시까지는 보낼 수 없어요. '
                  '광고 표시와 수신거부 안내는 자동으로 붙어요.',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    key: const ValueKey<String>('admin-push-send'),
                    onPressed: _canSend ? _send : null,
                    icon: const Icon(Icons.send, size: 18),
                    label: Text(_sending ? '보내는 중' : '보내기'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text('보낸 기록', style: AppTextStyles.cardTitle),
        const SizedBox(height: AppSpacing.md),
        if (_failed)
          Column(
            children: <Widget>[
              Text('불러오지 못했습니다.', style: AppTextStyles.body),
              TextButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          )
        else if (overview == null)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (overview.pushes.isEmpty)
          Text('아직 보낸 알림이 없습니다.', style: AppTextStyles.body)
        else
          for (final push in overview.pushes)
            Padding(
              key: ValueKey<String>('admin-push-${push.id}'),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _Notice(
                title: push.title,
                body: push.body,
                footer: '${_timeLabel(push.startedAt)} · ${_outcome(push)}',
              ),
            ),
      ],
    );
  }
}

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${adminDateLabel(value)} ${two(local.hour)}:${two(local.minute)}';
}

String _outcome(AdminMarketingPush push) => push.finishedAt == null
    ? '끝나지 않음'
    : '휴대폰 ${push.deviceCount ?? 0}대 중 ${push.sentCount ?? 0}대';

/// A notification's words in a card: the preview, and a past send.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.title,
    required this.body,
    this.footer,
    super.key,
  });

  final String title;
  final String body;
  final String? footer;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfacePrimary,
      border: Border.all(color: AppColors.borderSubtle),
      borderRadius: BorderRadius.circular(AppRadii.card),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(body, style: AppTextStyles.body),
          if (footer case final footer?) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(footer, style: AppTextStyles.caption),
          ],
        ],
      ),
    ),
  );
}
