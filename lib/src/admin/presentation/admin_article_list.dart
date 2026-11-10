import 'package:flutter/material.dart';

import '../../design/app_tokens.dart';
import '../../design/app_typography.dart';
import '../../features/editorial/presentation/widgets/editorial_media_image.dart';
import '../admin_editorial_models.dart';
import 'admin_widgets.dart';

/// Every post in a table: the status cards on top count the posts and
/// filter the table to one state, then search, then one row per post with
/// its quick actions.
class AdminArticleListPage extends StatefulWidget {
  const AdminArticleListPage({
    required this.articles,
    required this.role,
    required this.refreshing,
    required this.onRefresh,
    required this.onCreate,
    required this.onOpen,
    required this.onPreview,
    required this.onChangeStatus,
    this.onPublishInOrder,
    super.key,
  });

  final List<AdminEditorialArticle> articles;
  final AdminRole role;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onCreate;
  final ValueChanged<AdminEditorialArticle> onOpen;
  final ValueChanged<AdminEditorialArticle> onPreview;
  final void Function(AdminEditorialArticle article, AdminArticleStatus status)
  onChangeStatus;

  /// Publishes the posts one after another in the order given; `null` for
  /// a role that cannot publish, which hides the picking mode.
  final Future<void> Function(List<AdminEditorialArticle> articles)?
  onPublishInOrder;

  @override
  State<AdminArticleListPage> createState() => _AdminArticleListPageState();
}

class _AdminArticleListPageState extends State<AdminArticleListPage> {
  final TextEditingController _search = TextEditingController();
  AdminArticleStatus? _status;

  /// Picking mode: unpublished posts take a number in the order they are
  /// tapped, and that is the order they are published in.
  bool _picking = false;
  final List<String> _pickedIds = <String>[];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AdminEditorialArticle> get _visible {
    final query = _search.text.trim().toLowerCase();
    return <AdminEditorialArticle>[
      for (final article in widget.articles)
        if ((_status == null || article.status == _status) &&
            (query.isEmpty || article.body.toLowerCase().contains(query)))
          article,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  int _count(AdminArticleStatus status) =>
      widget.articles.where((article) => article.status == status).length;

  List<AdminEditorialArticle> get _picked => <AdminEditorialArticle>[
    for (final id in _pickedIds)
      for (final article in widget.articles)
        if (article.id == id) article,
  ];

  void _togglePicking() => setState(() {
    _picking = !_picking;
    _pickedIds.clear();
  });

  void _togglePicked(AdminEditorialArticle article) => setState(() {
    if (!_pickedIds.remove(article.id)) _pickedIds.add(article.id);
  });

  Future<void> _publishPicked() async {
    final picked = _picked;
    if (picked.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${picked.length}개를 발행할까요?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final (index, article) in picked.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  '${index + 1}. ${article.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '이 순서로 차례로 발행돼요. 탐색 탭은 최근 발행 순이라 마지막 글이 맨 위에 와요.',
              style: AppTextStyles.caption,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey<String>('admin-confirm-publish-picked'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('발행'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.onPublishInOrder!(picked);
    if (mounted) _togglePicking();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return ListView(
          padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('게시글', style: AppTextStyles.screenTitle),
                      const SizedBox(height: 2),
                      Text(
                        '탐색 탭에 보이는 술 이야기를 쓰고 발행해요.',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '새로고침',
                  onPressed: widget.refreshing ? null : widget.onRefresh,
                  icon: widget.refreshing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  key: const ValueKey<String>('admin-new-article'),
                  onPressed: widget.onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('새 게시글'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: <Widget>[
                _StatCard(
                  label: '전체',
                  count: widget.articles.length,
                  color: AppColors.actionPrimary,
                  selected: _status == null,
                  onTap: () => setState(() => _status = null),
                ),
                for (final status in AdminArticleStatus.values)
                  _StatCard(
                    label: status.label,
                    count: _count(status),
                    color: adminStatusColor(status),
                    selected: _status == status,
                    onTap: () => setState(() => _status = status),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('상태를 누르면 그 상태의 글만 보여요.', style: AppTextStyles.caption),
            const SizedBox(height: AppSpacing.xl),
            Material(
              color: AppColors.surfacePrimary,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppColors.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: compact ? constraints.maxWidth - 64 : 300,
                          child: TextField(
                            key: const ValueKey<String>('admin-list-search'),
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 20),
                              hintText: '글 내용으로 찾기',
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: '지우기',
                                      onPressed: () => setState(_search.clear),
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                            ),
                          ),
                        ),
                        Text(
                          '${_status?.label ?? '전체'} ${visible.length}개',
                          key: const ValueKey<String>('admin-list-count'),
                          style: AppTextStyles.caption,
                        ),
                        if (widget.onPublishInOrder != null && !_picking)
                          TextButton.icon(
                            key: const ValueKey<String>('admin-pick-publish'),
                            onPressed: _togglePicking,
                            icon: const Icon(Icons.checklist, size: 18),
                            label: const Text('골라서 발행'),
                          ),
                        if (_picking) ...<Widget>[
                          Text(
                            _pickedIds.isEmpty
                                ? '발행할 글을 순서대로 눌러요'
                                : '${_pickedIds.length}개 고름 · 누른 순서대로 발행돼요',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.actionPrimary,
                            ),
                          ),
                          FilledButton(
                            key: const ValueKey<String>('admin-publish-picked'),
                            onPressed: _pickedIds.isEmpty
                                ? null
                                : _publishPicked,
                            child: Text('${_pickedIds.length}개 발행'),
                          ),
                          TextButton(
                            onPressed: _togglePicking,
                            child: const Text('취소'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (!compact) const _HeaderRow(),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 56),
                      child: Column(
                        children: <Widget>[
                          const Icon(
                            Icons.article_outlined,
                            size: 36,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            widget.articles.isEmpty
                                ? '아직 게시글이 없어요. 첫 글을 써 보세요.'
                                : '조건에 맞는 게시글이 없어요.',
                            style: AppTextStyles.body,
                          ),
                        ],
                      ),
                    )
                  else
                    for (final (index, article) in visible.indexed) ...<Widget>[
                      if (index > 0) const Divider(height: 1),
                      _ArticleRow(
                        article: article,
                        compact: compact,
                        canPublish: widget.role.canPublish,
                        picking: _picking,
                        pickedIndex: _pickedIds.indexOf(article.id),
                        onOpen: () => widget.onOpen(article),
                        onPick: () => _togglePicked(article),
                        onPreview: () => widget.onPreview(article),
                        onChangeStatus: (status) =>
                            widget.onChangeStatus(article, status),
                      ),
                    ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? Color.alphaBlend(
            color.withValues(alpha: .08),
            AppColors.surfacePrimary,
          )
        : AppColors.surfacePrimary,
    shape: RoundedRectangleBorder(
      side: BorderSide(
        color: selected ? color : AppColors.borderSubtle,
        width: selected ? 1.5 : 1,
      ),
      borderRadius: BorderRadius.circular(AppRadii.compactCard),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey<String>('admin-stat-$label'),
      onTap: onTap,
      child: SizedBox(
        width: 150,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: AppTextStyles.caption),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$count',
                style: AppTextStyles.screenTitle.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.labelSmall.copyWith(
      color: AppColors.textTertiary,
    );
    return Container(
      color: AppColors.surfaceSoft,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 56 + AppSpacing.md),
          Expanded(child: Text('글', style: style)),
          SizedBox(width: 80, child: Text('상태', style: style)),
          SizedBox(width: 56, child: Text('사진', style: style)),
          SizedBox(width: 96, child: Text('수정일', style: style)),
          const SizedBox(width: 96),
        ],
      ),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  const _ArticleRow({
    required this.article,
    required this.compact,
    required this.canPublish,
    required this.picking,
    required this.pickedIndex,
    required this.onOpen,
    required this.onPick,
    required this.onPreview,
    required this.onChangeStatus,
  });

  final AdminEditorialArticle article;
  final bool compact;
  final bool canPublish;

  /// In picking mode an unpublished row toggles its place in the publish
  /// order instead of opening; a published row sits out, dimmed.
  final bool picking;

  /// Position in the publish order, or -1 when not picked.
  final int pickedIndex;
  final VoidCallback onOpen;
  final VoidCallback onPick;
  final VoidCallback onPreview;
  final ValueChanged<AdminArticleStatus> onChangeStatus;

  bool get _pickable => article.status != AdminArticleStatus.published;

  @override
  Widget build(BuildContext context) {
    final thumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: SizedBox(
        width: 56,
        height: 70,
        child: EditorialMediaImage(media: article.coverMedia),
      ),
    );
    final title = Text(
      article.label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.cardTitle,
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          key: ValueKey<String>('admin-preview-${article.id}'),
          tooltip: '미리보기',
          onPressed: onPreview,
          icon: const Icon(Icons.visibility_outlined, size: 20),
        ),
        PopupMenuButton<AdminArticleStatus>(
          key: ValueKey<String>('admin-menu-${article.id}'),
          tooltip: '더 보기',
          icon: const Icon(Icons.more_horiz, size: 20),
          onSelected: onChangeStatus,
          itemBuilder: (context) => <PopupMenuEntry<AdminArticleStatus>>[
            if (canPublish && article.status != AdminArticleStatus.published)
              const PopupMenuItem<AdminArticleStatus>(
                value: AdminArticleStatus.published,
                child: Text('발행'),
              ),
            if (canPublish && article.status == AdminArticleStatus.published)
              const PopupMenuItem<AdminArticleStatus>(
                value: AdminArticleStatus.withdrawn,
                child: Text('철회'),
              ),
            if (!canPublish)
              const PopupMenuItem<AdminArticleStatus>(
                enabled: false,
                child: Text('발행은 관리자만 할 수 있어요'),
              ),
          ],
        ),
      ],
    );

    final pickMark = !picking
        ? null
        : !_pickable
        ? const SizedBox(width: 28)
        : Container(
            key: ValueKey<String>('admin-pick-${article.id}'),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pickedIndex >= 0
                  ? AppColors.actionPrimary
                  : AppColors.surfacePrimary,
              border: Border.all(
                color: pickedIndex >= 0
                    ? AppColors.actionPrimary
                    : AppColors.borderStrong,
                width: 1.5,
              ),
            ),
            child: pickedIndex >= 0
                ? Text(
                    '${pickedIndex + 1}',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textOnPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          );

    return Opacity(
      opacity: picking && !_pickable ? .45 : 1,
      child: InkWell(
        key: ValueKey<String>('admin-article-${article.id}'),
        onTap: picking ? (_pickable ? onPick : null) : onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: compact
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (pickMark != null) ...<Widget>[
                      pickMark,
                      const SizedBox(width: AppSpacing.md),
                    ],
                    thumbnail,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          title,
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              AdminStatusChip(status: article.status),
                              Text(
                                '사진 ${article.gallery.length}장 · ${adminDateLabel(article.updatedAt)}',
                                style: AppTextStyles.caption,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    actions,
                  ],
                )
              : Row(
                  children: <Widget>[
                    if (pickMark != null) ...<Widget>[
                      pickMark,
                      const SizedBox(width: AppSpacing.md),
                    ],
                    thumbnail,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: title),
                    SizedBox(
                      width: 80,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AdminStatusChip(status: article.status),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${article.gallery.length}장',
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                    SizedBox(
                      width: 96,
                      child: Text(
                        adminDateLabel(article.updatedAt),
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                    SizedBox(width: 96, child: actions),
                  ],
                ),
        ),
      ),
    );
  }
}
