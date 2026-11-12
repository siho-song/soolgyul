import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/app_tokens.dart';
import '../../design/app_typography.dart';
import '../data/admin_editorial_gateway.dart';
import '../admin_editorial_models.dart';
import 'admin_article_editor.dart';
import 'admin_article_list.dart';
import 'admin_article_preview.dart';
import 'admin_site_posts_page.dart';
import 'admin_support_inbox_page.dart';
import 'admin_widgets.dart';

/// The admin shell: a sidebar with the account on wide screens, and the
/// post list, the editor, the notices and FAQ or (for an admin) the support
/// inbox as the page.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    required this.gateway,
    required this.session,
    required this.initialBootstrap,
    this.pickPhotos,
    super.key,
  });

  final AdminEditorialGateway gateway;
  final AdminAuthSession session;
  final AdminEditorialBootstrap initialBootstrap;

  /// Replaces the system photo picker in tests.
  final AdminPhotoPicker? pickPhotos;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

enum _Page { list, editor, sitePosts, inbox }

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late AdminEditorialBootstrap _bootstrap;
  _Page _page = _Page.list;
  String? _selectedArticleId;
  int _newDraftVersion = 0;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _bootstrap = widget.initialBootstrap;
  }

  AdminEditorialArticle? get _selectedArticle {
    final selectedId = _selectedArticleId;
    if (selectedId == null) return null;
    for (final article in _bootstrap.articles) {
      if (article.id == selectedId) return article;
    }
    return null;
  }

  Future<void> _refresh({String? selectArticleId}) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final bootstrap = await widget.gateway.loadBootstrap();
      if (!mounted || bootstrap == null) return;
      setState(() {
        _bootstrap = bootstrap;
        if (selectArticleId != null) _selectedArticleId = selectArticleId;
      });
    } catch (_) {
      if (mounted) _showMessage('새로고침하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Whether the open editor holds changes not saved yet, as it last said.
  /// Only read, never shown, so it changes without a rebuild.
  bool _editorDirty = false;

  void _show(_Page page) => setState(() {
    _page = page;
    _editorDirty = false;
  });

  void _openList() => _show(_Page.list);

  void _openSitePosts() => _show(_Page.sitePosts);

  void _openInbox() => _show(_Page.inbox);

  void _openArticle(AdminEditorialArticle article) {
    _selectedArticleId = article.id;
    _show(_Page.editor);
  }

  void _createDraft() {
    _selectedArticleId = null;
    _newDraftVersion += 1;
    _show(_Page.editor);
  }

  /// The sidebar and signing out leave the editor without its back arrow;
  /// with changes not saved they ask first, as the arrow does.
  Future<void> _leaveEditorFor(FutureOr<void> Function() go) async {
    if (_page == _Page.editor && _editorDirty) {
      if (!await confirmDiscardEdits(context) || !mounted) return;
    }
    await go();
  }

  Future<void> _signOut() => _leaveEditorFor(() async {
    try {
      await widget.gateway.signOut();
    } catch (_) {
      if (mounted) _showMessage('로그아웃하지 못했습니다.');
    }
  });

  /// True while a publish or withdraw from the list is on its way; another
  /// one asked meanwhile is dropped, so a post is not published twice.
  bool _changingStatus = false;

  Future<void> _changeStatus(
    AdminEditorialArticle article,
    AdminArticleStatus status,
  ) async {
    if (_changingStatus) return;
    _changingStatus = true;
    try {
      await widget.gateway.changeStatus(article.id, status);
      if (!mounted) return;
      _showMessage(
        status == AdminArticleStatus.published
            ? '「${article.label}」을 발행했습니다.'
            : '「${article.label}」을 철회했습니다.',
      );
      await _refresh();
    } catch (_) {
      if (mounted) _showMessage('상태를 변경하지 못했습니다.');
    } finally {
      _changingStatus = false;
    }
  }

  /// Publishes in the given order, one at a time, so the feed (newest
  /// publish first) ends with the last one on top. Stops at the first
  /// failure and says how far it got.
  Future<void> _publishInOrder(List<AdminEditorialArticle> articles) async {
    if (_changingStatus) return;
    _changingStatus = true;
    var done = 0;
    try {
      for (final article in articles) {
        await widget.gateway.changeStatus(
          article.id,
          AdminArticleStatus.published,
        );
        done += 1;
      }
      if (mounted) _showMessage('$done개를 고른 순서대로 발행했습니다.');
    } catch (_) {
      if (mounted) {
        _showMessage(
          done == 0 ? '발행하지 못했습니다.' : '$done개까지 발행하고 멈췄습니다. 나머지를 다시 발행해 주세요.',
        );
      }
    } finally {
      _changingStatus = false;
    }
    await _refresh();
  }

  void _preview(AdminEditorialArticle article) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: AppColors.surfaceSoft,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          article.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.cardTitle,
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AdminArticlePreview(
                    body: article.body,
                    interestKeys: article.interestKeys,
                    gallery: article.gallery,
                    instagramUrl: article.instagramUrl,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final page = switch (_page) {
      _Page.list => AdminArticleListPage(
        articles: _bootstrap.articles,
        role: _bootstrap.role,
        refreshing: _refreshing,
        onRefresh: _refresh,
        onCreate: _createDraft,
        onOpen: _openArticle,
        onPreview: _preview,
        onChangeStatus: _changeStatus,
        onPublishInOrder: _bootstrap.role.canPublish ? _publishInOrder : null,
      ),
      _Page.editor => AdminArticleEditor(
        key: ValueKey<String>(_selectedArticleId ?? 'new-$_newDraftVersion'),
        gateway: widget.gateway,
        role: _bootstrap.role,
        article: _selectedArticle,
        onChanged: (articleId) => _refresh(selectArticleId: articleId),
        onDeleted: () async {
          setState(() {
            _selectedArticleId = null;
            _page = _Page.list;
          });
          await _refresh();
        },
        onBack: _openList,
        onDirtyChanged: (dirty) => _editorDirty = dirty,
        pickPhotos: widget.pickPhotos,
      ),
      _Page.sitePosts => AdminSitePostsPage(
        gateway: widget.gateway,
        role: _bootstrap.role,
      ),
      _Page.inbox => AdminSupportInboxPage(gateway: widget.gateway),
    };
    final readsInbox = _bootstrap.role == AdminRole.admin;

    if (wide) {
      return Scaffold(
        backgroundColor: AppColors.surfaceCanvas,
        body: Row(
          children: <Widget>[
            _SideBar(
              role: _bootstrap.role,
              email: widget.session.email,
              page: _page,
              onArticles: () => _leaveEditorFor(_openList),
              onCreate: () => _leaveEditorFor(_createDraft),
              onSitePosts: () => _leaveEditorFor(_openSitePosts),
              onInbox: readsInbox ? () => _leaveEditorFor(_openInbox) : null,
              onSignOut: _signOut,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: page),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.surfaceCanvas,
      // The editor has its own header with a back arrow, so nothing here
      // leaves it.
      appBar: _page == _Page.editor
          ? null
          : AppBar(
              title: Row(
                children: <Widget>[
                  const Icon(
                    Icons.admin_panel_settings_outlined,
                    color: AppColors.actionPrimary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('술결 관리자', style: AppTextStyles.appHeaderTitle),
                ],
              ),
              actions: <Widget>[
                if (_page != _Page.list)
                  IconButton(
                    tooltip: '게시글',
                    onPressed: _openList,
                    icon: const Icon(Icons.article_outlined),
                  ),
                if (_page != _Page.sitePosts)
                  IconButton(
                    key: const ValueKey<String>('admin-nav-site-posts-compact'),
                    tooltip: '공지·FAQ',
                    onPressed: _openSitePosts,
                    icon: const Icon(Icons.campaign_outlined),
                  ),
                if (readsInbox && _page != _Page.inbox)
                  IconButton(
                    key: const ValueKey<String>('admin-nav-inbox-compact'),
                    tooltip: '문의',
                    onPressed: _openInbox,
                    icon: const Icon(Icons.mail_outline),
                  ),
                _RoleBadge(role: _bootstrap.role),
                IconButton(
                  tooltip: '로그아웃',
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),
      body: page,
    );
  }
}

class _SideBar extends StatelessWidget {
  const _SideBar({
    required this.role,
    required this.email,
    required this.page,
    required this.onArticles,
    required this.onCreate,
    required this.onSitePosts,
    required this.onInbox,
    required this.onSignOut,
  });

  final AdminRole role;
  final String? email;
  final _Page page;
  final VoidCallback onArticles;
  final VoidCallback onCreate;
  final VoidCallback onSitePosts;

  /// Null for an editor, who does not read the support inbox.
  final VoidCallback? onInbox;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfacePrimary,
    child: SizedBox(
      width: 232,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.xl,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.admin_panel_settings_outlined,
                    color: AppColors.actionPrimary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('술결 관리자', style: AppTextStyles.appHeaderTitle),
                ],
              ),
            ),
            _NavItem(
              key: const ValueKey<String>('admin-nav-articles'),
              icon: Icons.article_outlined,
              label: '게시글',
              selected: page == _Page.list,
              onTap: onArticles,
            ),
            const SizedBox(height: AppSpacing.xs),
            _NavItem(
              key: const ValueKey<String>('admin-nav-new'),
              icon: Icons.add_circle_outline,
              label: '새 게시글',
              selected: false,
              onTap: onCreate,
            ),
            const SizedBox(height: AppSpacing.xs),
            _NavItem(
              key: const ValueKey<String>('admin-nav-site-posts'),
              icon: Icons.campaign_outlined,
              label: '공지·FAQ',
              selected: page == _Page.sitePosts,
              onTap: onSitePosts,
            ),
            if (onInbox case final onInbox?) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              _NavItem(
                key: const ValueKey<String>('admin-nav-inbox'),
                icon: Icons.mail_outline,
                label: '문의',
                selected: page == _Page.inbox,
                onTap: onInbox,
              ),
            ],
            const Spacer(),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _RoleBadge(role: role),
                  if (email case final email?) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onSignOut,
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: AppColors.textSecondary,
              ),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('로그아웃'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.surfaceSoft : Colors.transparent,
    borderRadius: BorderRadius.circular(AppRadii.control),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 20,
              color: selected
                  ? AppColors.actionPrimary
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              label,
              style: AppTextStyles.body.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final AdminRole role;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(AppRadii.chip),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        role == AdminRole.admin ? 'ADMIN' : 'EDITOR',
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.actionPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
