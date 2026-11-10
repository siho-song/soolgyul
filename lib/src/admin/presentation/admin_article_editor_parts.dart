part of 'admin_article_editor.dart';

// The editor's header, photo drop zone and gallery strip.

/// Title, status and the actions: back, preview (narrow screens), save,
/// publish or withdraw, delete.
class _Header extends StatelessWidget {
  const _Header({
    required this.article,
    required this.dirty,
    required this.busy,
    required this.compact,
    required this.showPreview,
    required this.canPublish,
    required this.canDelete,
    required this.onBack,
    required this.onTogglePreview,
    required this.onSave,
    required this.onPublish,
    required this.onWithdraw,
    required this.onDelete,
  });

  final AdminEditorialArticle? article;
  final bool dirty;
  final bool busy;
  final bool compact;
  final bool showPreview;
  final bool canPublish;
  final bool canDelete;
  final VoidCallback onBack;
  final VoidCallback onTogglePreview;
  final VoidCallback onSave;
  final VoidCallback onPublish;
  final VoidCallback onWithdraw;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfacePrimary,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            key: const ValueKey<String>('admin-editor-back'),
            tooltip: '게시글 목록',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  article == null ? '새 게시글' : article!.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.sectionTitle,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    if (article case final article?) ...<Widget>[
                      AdminStatusChip(status: article.status),
                      Text(
                        '수정 ${adminDateLabel(article.updatedAt)}',
                        style: AppTextStyles.caption,
                      ),
                    ] else
                      Text('저장하면 사진을 올릴 수 있어요.', style: AppTextStyles.caption),
                    if (dirty)
                      Text(
                        '저장 안 됨',
                        key: const ValueKey<String>('admin-dirty'),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.actionPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (compact)
            IconButton(
              key: const ValueKey<String>('admin-toggle-preview'),
              tooltip: showPreview ? '편집으로' : '미리보기',
              onPressed: onTogglePreview,
              isSelected: showPreview,
              icon: const Icon(Icons.phone_iphone_outlined),
            ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            key: const ValueKey<String>('admin-save-article'),
            onPressed: busy ? null : onSave,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('저장'),
          ),
          if (canPublish) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            if (article?.status != AdminArticleStatus.published)
              OutlinedButton(
                key: const ValueKey<String>('admin-publish-article'),
                onPressed: busy ? null : onPublish,
                child: const Text('발행'),
              )
            else
              OutlinedButton(
                key: const ValueKey<String>('admin-withdraw-article'),
                onPressed: busy ? null : onWithdraw,
                child: const Text('철회'),
              ),
          ],
          if (canDelete) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              tooltip: '초안 삭제',
              onPressed: busy ? null : onDelete,
              color: AppColors.actionDestructive,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      ),
    ),
  );
}

/// The place to drop files, which also opens the picker when clicked.
class _DropZone extends StatelessWidget {
  const _DropZone({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceSoft,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.borderStrong),
      borderRadius: BorderRadius.circular(AppRadii.compactCard),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: const ValueKey<String>('admin-drop-zone'),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Column(
          children: <Widget>[
            const Icon(
              Icons.cloud_upload_outlined,
              size: 28,
              color: AppColors.actionPrimary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '사진을 여기로 끌어다 놓거나 눌러서 골라요',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              'JPG, PNG, WEBP · 여러 장 한 번에 · 인스타그램처럼 3:4가 가장 잘 맞아요 · 올리면 1080×1440 JPEG로 줄여요',
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    ),
  );
}

/// The gallery in reader order. Photos drag to a new place or step with the
/// arrows; the first one is the cover.
class _GalleryStrip extends StatelessWidget {
  const _GalleryStrip({
    required this.media,
    required this.enabled,
    required this.onDelete,
    required this.onReorder,
  });

  final List<EditorialMediaAsset> media;
  final bool enabled;
  final ValueChanged<EditorialMediaAsset> onDelete;
  final void Function(int from, int to) onReorder;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) {
      return Text('아직 올린 사진이 없어요. 첫 사진이 표지가 돼요.', style: AppTextStyles.caption);
    }
    return SizedBox(
      height: 256,
      child: ReorderableListView.builder(
        key: const ValueKey<String>('admin-gallery'),
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: media.length,
        onReorderItem: onReorder,
        itemBuilder: (context, index) {
          final value = media[index];
          return Padding(
            key: ValueKey<String>('admin-media-${value.id}'),
            padding: EdgeInsets.only(
              right: index == media.length - 1 ? 0 : AppSpacing.md,
            ),
            child: _GalleryTile(
              media: value,
              label: index == 0 ? '표지' : '${index + 1}번째',
              enabled: enabled,
              index: index,
              canMoveLeft: index > 0,
              canMoveRight: index < media.length - 1,
              onMoveLeft: () => onReorder(index, index - 1),
              onMoveRight: () => onReorder(index, index + 1),
              onDelete: value.isBundledAsset ? null : () => onDelete(value),
            ),
          );
        },
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  static const height = 200.0;

  const _GalleryTile({
    required this.media,
    required this.label,
    required this.enabled,
    required this.index,
    required this.canMoveLeft,
    required this.canMoveRight,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onDelete,
  });

  final EditorialMediaAsset media;
  final String label;
  final bool enabled;
  final int index;
  final bool canMoveLeft;
  final bool canMoveRight;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: SizedBox(
        width: _GalleryTile.height * editorialPhotoAspectRatio,
        height: _GalleryTile.height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            EditorialMediaImage(media: media),
            Positioned(
              left: AppSpacing.xs,
              top: AppSpacing.xs,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: index == 0 ? AppColors.actionPrimary : AppColors.scrim,
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  child: Text(
                    label,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textOnPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            if (enabled)
              const Positioned(
                right: AppSpacing.xs,
                top: AppSpacing.xs,
                child: Icon(
                  Icons.drag_indicator,
                  size: 18,
                  color: AppColors.textOnPrimary,
                  shadows: <Shadow>[Shadow(blurRadius: 4)],
                ),
              ),
          ],
        ),
      ),
    );
    return SizedBox(
      width: _GalleryTile.height * editorialPhotoAspectRatio,
      child: Column(
        children: <Widget>[
          if (enabled)
            ReorderableDragStartListener(index: index, child: image)
          else
            image,
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                key: ValueKey<String>('admin-media-left-${media.id}'),
                tooltip: '왼쪽으로',
                visualDensity: VisualDensity.compact,
                onPressed: enabled && canMoveLeft ? onMoveLeft : null,
                icon: const Icon(Icons.chevron_left, size: 20),
              ),
              IconButton(
                key: ValueKey<String>('admin-media-right-${media.id}'),
                tooltip: '오른쪽으로',
                visualDensity: VisualDensity.compact,
                onPressed: enabled && canMoveRight ? onMoveRight : null,
                icon: const Icon(Icons.chevron_right, size: 20),
              ),
              if (onDelete != null)
                IconButton(
                  key: ValueKey<String>('admin-media-delete-${media.id}'),
                  tooltip: '삭제',
                  visualDensity: VisualDensity.compact,
                  color: AppColors.actionDestructive,
                  onPressed: enabled ? onDelete : null,
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
