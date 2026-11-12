import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/app_tokens.dart';
import '../../design/app_typography.dart';
import '../admin_editorial_models.dart';
import '../data/admin_editorial_gateway.dart';
import 'admin_widgets.dart';

/// The notices and FAQ answers soolgyul.com shows: one list per kind, and a
/// dialog that writes, publishes, withdraws or deletes one of them. Notices
/// list newest first, FAQ answers in their order.
class AdminSitePostsPage extends StatefulWidget {
  const AdminSitePostsPage({
    required this.gateway,
    required this.role,
    super.key,
  });

  final AdminEditorialGateway gateway;
  final AdminRole role;

  @override
  State<AdminSitePostsPage> createState() => _AdminSitePostsPageState();
}

class _AdminSitePostsPageState extends State<AdminSitePostsPage> {
  AdminSitePostKind _kind = AdminSitePostKind.notice;
  List<AdminSitePost>? _posts;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final posts = await widget.gateway.fetchSitePosts();
      if (mounted) setState(() => _posts = posts);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  List<AdminSitePost> get _visible {
    final posts = <AdminSitePost>[
      for (final post in _posts ?? const <AdminSitePost>[])
        if (post.kind == _kind) post,
    ];
    if (_kind == AdminSitePostKind.notice) {
      posts.sort(
        (a, b) => (b.publishedAt ?? b.updatedAt).compareTo(
          a.publishedAt ?? a.updatedAt,
        ),
      );
    }
    return posts;
  }

  Future<void> _open(AdminSitePost? post) async {
    final changed = await showDialog<bool>(
      context: context,
      // A stray click beside the dialog must not throw away what was typed;
      // it closes with 닫기.
      barrierDismissible: false,
      builder: (context) => _SitePostDialog(
        gateway: widget.gateway,
        role: widget.role,
        kind: _kind,
        post: post,
        nextSortOrder: _visible.fold<int>(
          1,
          (next, post) => post.sortOrder >= next ? post.sortOrder + 1 : next,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    final visible = _visible;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text('공지·FAQ', style: AppTextStyles.screenTitle)),
            FilledButton.icon(
              key: const ValueKey<String>('admin-site-post-new'),
              onPressed: () => _open(null),
              icon: const Icon(Icons.add),
              label: Text(_kind == AdminSitePostKind.notice ? '새 공지' : '새 질문'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '발행한 글은 soolgyul.com의 공지사항·자주 묻는 질문 페이지에 바로 보여요.',
          style: AppTextStyles.caption,
        ),
        const SizedBox(height: AppSpacing.xl),
        SegmentedButton<AdminSitePostKind>(
          segments: <ButtonSegment<AdminSitePostKind>>[
            for (final kind in AdminSitePostKind.values)
              ButtonSegment<AdminSitePostKind>(
                value: kind,
                label: Text(kind.label),
              ),
          ],
          selected: <AdminSitePostKind>{_kind},
          onSelectionChanged: (selected) =>
              setState(() => _kind = selected.single),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_failed)
          Column(
            children: <Widget>[
              Text('불러오지 못했습니다.', style: AppTextStyles.body),
              TextButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          )
        else if (posts == null)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(
              _kind == AdminSitePostKind.notice
                  ? '아직 공지가 없습니다.'
                  : '아직 질문이 없습니다.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
          )
        else
          for (final post in visible)
            Card(
              key: ValueKey<String>('admin-site-post-${post.id}'),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              color: AppColors.surfacePrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppColors.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: ListTile(
                onTap: () => _open(post),
                title: Text(
                  post.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  post.kind == AdminSitePostKind.faq
                      ? '순서 ${post.sortOrder}'
                      : adminDateLabel(post.publishedAt ?? post.updatedAt),
                  style: AppTextStyles.caption,
                ),
                trailing: AdminStatusChip(status: post.status),
              ),
            ),
      ],
    );
  }
}

class _SitePostDialog extends StatefulWidget {
  const _SitePostDialog({
    required this.gateway,
    required this.role,
    required this.kind,
    required this.post,
    required this.nextSortOrder,
  });

  final AdminEditorialGateway gateway;
  final AdminRole role;
  final AdminSitePostKind kind;
  final AdminSitePost? post;

  /// The order a new FAQ answer gets: after the last one.
  final int nextSortOrder;

  @override
  State<_SitePostDialog> createState() => _SitePostDialogState();
}

class _SitePostDialogState extends State<_SitePostDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.post?.title,
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.post?.body,
  );
  late final TextEditingController _order = TextEditingController(
    text: '${widget.post?.sortOrder ?? widget.nextSortOrder}',
  );
  bool _busy = false;
  String? _error;

  AdminArticleStatus get _status =>
      widget.post?.status ?? AdminArticleStatus.draft;

  /// An editor changes drafts only; a published or withdrawn one is read.
  bool get _editable =>
      widget.role.canPublish || _status == AdminArticleStatus.draft;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _save(AdminArticleStatus status) async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '제목을 입력해 주세요.');
      return;
    }
    await _run(
      () => widget.gateway.saveSitePost(
        AdminSitePostDraft(
          id: widget.post?.id,
          kind: widget.kind,
          title: _title.text.trim(),
          body: _body.text.trim(),
          sortOrder: int.tryParse(_order.text.trim()) ?? widget.nextSortOrder,
          status: status,
        ),
      ),
      failure: '저장하지 못했습니다.',
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('삭제할까요?'),
        content: const Text('삭제한 글은 되돌릴 수 없습니다.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey<String>('admin-site-post-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => widget.gateway.deleteSitePost(widget.post!.id),
      failure: '삭제하지 못했습니다.',
    );
  }

  Future<void> _run(
    Future<Object?> Function() work, {
    required String failure,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final faq = widget.kind == AdminSitePostKind.faq;
    final post = widget.post;
    final canPublish = widget.role.canPublish;
    final enabled = _editable && !_busy;
    return AlertDialog(
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              post == null ? (faq ? '새 질문' : '새 공지') : widget.kind.label,
            ),
          ),
          AdminStatusChip(status: _status),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                key: const ValueKey<String>('admin-site-post-title'),
                controller: _title,
                enabled: enabled,
                decoration: InputDecoration(labelText: faq ? '질문' : '제목'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey<String>('admin-site-post-body'),
                controller: _body,
                enabled: enabled,
                minLines: 6,
                maxLines: 14,
                decoration: InputDecoration(
                  labelText: faq ? '답변' : '본문',
                  alignLabelWithHint: true,
                ),
              ),
              if (faq) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const ValueKey<String>('admin-site-post-order'),
                  controller: _order,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '순서',
                    helperText: '작은 숫자가 위에 와요.',
                  ),
                ),
              ],
              if (!_editable) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  '발행했거나 내린 글은 ADMIN만 고칠 수 있습니다.',
                  style: AppTextStyles.caption,
                ),
              ],
              if (_error case final error?) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  error,
                  style: AppTextStyles.body.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (post != null && canPublish)
          TextButton(
            key: const ValueKey<String>('admin-site-post-delete'),
            onPressed: _busy ? null : _delete,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.actionDestructive,
            ),
            child: const Text('삭제'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('닫기'),
        ),
        if (_editable && _status != AdminArticleStatus.published)
          OutlinedButton(
            key: const ValueKey<String>('admin-site-post-save-draft'),
            onPressed: enabled ? () => _save(AdminArticleStatus.draft) : null,
            child: const Text('초안 저장'),
          ),
        if (canPublish && _status == AdminArticleStatus.published)
          OutlinedButton(
            key: const ValueKey<String>('admin-site-post-withdraw'),
            onPressed: enabled
                ? () => _save(AdminArticleStatus.withdrawn)
                : null,
            child: const Text('내리기'),
          ),
        if (canPublish)
          FilledButton(
            key: const ValueKey<String>('admin-site-post-publish'),
            onPressed: enabled
                ? () => _save(AdminArticleStatus.published)
                : null,
            child: Text(_status == AdminArticleStatus.published ? '저장' : '발행'),
          ),
      ],
    );
  }
}
