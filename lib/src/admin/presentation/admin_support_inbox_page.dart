import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/app_tokens.dart';
import '../../design/app_typography.dart';
import '../admin_editorial_models.dart';
import '../data/admin_editorial_gateway.dart';
import 'admin_widgets.dart';

/// The members' questions from the app's support form, open ones first. An
/// inquiry opens in a dialog with its words, reply address and photos, and
/// is marked answered once the reply mail is out.
class AdminSupportInboxPage extends StatefulWidget {
  const AdminSupportInboxPage({required this.gateway, super.key});

  final AdminEditorialGateway gateway;

  @override
  State<AdminSupportInboxPage> createState() => _AdminSupportInboxPageState();
}

class _AdminSupportInboxPageState extends State<AdminSupportInboxPage> {
  List<AdminSupportInquiry>? _inquiries;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final inquiries = await widget.gateway.fetchSupportInquiries();
      if (mounted) setState(() => _inquiries = inquiries);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _open(AdminSupportInquiry inquiry) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _InquiryDialog(gateway: widget.gateway, inquiry: inquiry),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final inquiries = _inquiries;
    final open = inquiries?.where((inquiry) => inquiry.answeredAt == null);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      children: <Widget>[
        Text('문의', style: AppTextStyles.screenTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          open == null ? '앱 고객센터로 들어온 문의예요.' : '답변을 기다리는 문의 ${open.length}건',
          style: AppTextStyles.caption,
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_failed)
          Column(
            children: <Widget>[
              Text('불러오지 못했습니다.', style: AppTextStyles.body),
              TextButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          )
        else if (inquiries == null)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (inquiries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(
              '아직 문의가 없습니다.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
          )
        else
          for (final inquiry in inquiries)
            Card(
              key: ValueKey<String>('admin-inquiry-${inquiry.id}'),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              color: AppColors.surfacePrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppColors.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: ListTile(
                onTap: () => _open(inquiry),
                title: Text(
                  inquiry.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${inquiry.type.label} · ${adminDateLabel(inquiry.createdAt)}'
                  '${inquiry.attachmentPaths.isEmpty ? '' : ' · 사진 ${inquiry.attachmentPaths.length}장'}',
                  style: AppTextStyles.caption,
                ),
                trailing: _AnsweredChip(answered: inquiry.answeredAt != null),
              ),
            ),
      ],
    );
  }
}

class _AnsweredChip extends StatelessWidget {
  const _AnsweredChip({required this.answered});

  final bool answered;

  @override
  Widget build(BuildContext context) {
    final color = answered
        ? AppColors.textTertiary
        : AppColors.preferencePrimary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        child: Text(
          answered ? '답변 완료' : '답변 대기',
          style: AppTextStyles.labelSmall.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _InquiryDialog extends StatefulWidget {
  const _InquiryDialog({required this.gateway, required this.inquiry});

  final AdminEditorialGateway gateway;
  final AdminSupportInquiry inquiry;

  @override
  State<_InquiryDialog> createState() => _InquiryDialogState();
}

class _InquiryDialogState extends State<_InquiryDialog> {
  late final Future<List<String>> _photos = widget.gateway.inquiryPhotoUrls(
    widget.inquiry.attachmentPaths,
  );
  bool _busy = false;
  String? _error;

  bool get _answered => widget.inquiry.answeredAt != null;

  Future<void> _toggleAnswered() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.gateway.setSupportInquiryAnswered(
        widget.inquiry.id,
        answered: !_answered,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '바꾸지 못했습니다.';
        });
      }
    }
  }

  Future<void> _copyEmail() async {
    var copied = true;
    try {
      await Clipboard.setData(ClipboardData(text: widget.inquiry.replyEmail));
    } catch (_) {
      // A browser may refuse the clipboard.
      copied = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(copied ? '메일 주소를 복사했습니다.' : '메일 주소를 복사하지 못했습니다.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final inquiry = widget.inquiry;
    return AlertDialog(
      title: Text(
        '${inquiry.type.label} · ${adminDateLabel(inquiry.createdAt)}',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: SelectableText(
                      inquiry.replyEmail,
                      style: AppTextStyles.body,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('admin-inquiry-copy-email'),
                    tooltip: '메일 주소 복사',
                    onPressed: _copyEmail,
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SelectableText(inquiry.content, style: AppTextStyles.body),
              if (inquiry.attachmentPaths.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                FutureBuilder<List<String>>(
                  future: _photos,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text(
                        '사진을 불러오지 못했습니다.',
                        style: AppTextStyles.caption,
                      );
                    }
                    final urls = snapshot.data;
                    if (urls == null) {
                      return const LinearProgressIndicator();
                    }
                    return Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        for (final url in urls)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              AppRadii.control,
                            ),
                            child: Image.network(
                              url,
                              width: 168,
                              height: 168,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox(
                                width: 168,
                                height: 168,
                                child: Center(child: Text('사진을 불러오지 못했습니다.')),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
              if (_error case final error?) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  error,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.actionDestructive,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('닫기'),
        ),
        FilledButton(
          key: const ValueKey<String>('admin-inquiry-answered'),
          onPressed: _busy ? null : _toggleAnswered,
          child: Text(_answered ? '다시 답변 대기로' : '답변 완료로 표시'),
        ),
      ],
    );
  }
}
