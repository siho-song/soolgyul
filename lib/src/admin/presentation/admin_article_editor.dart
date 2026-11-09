import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../design/app_tokens.dart';
import '../../design/app_typography.dart';
import '../../features/editorial/data/editorial_article.dart';
import '../../features/editorial/presentation/widgets/editorial_media_image.dart';
import '../../features/profile/data/profile_setup_draft.dart';
import '../data/admin_editorial_gateway.dart';
import '../admin_editorial_models.dart';
import 'admin_article_preview.dart';
import 'admin_file_drop.dart';
import 'admin_photo_encoder.dart';
import 'admin_widgets.dart';

/// Opens the system picker and returns the chosen photos; tests inject one.
typedef AdminPhotoPicker = Future<List<AdminDroppedFile>> Function();

/// Post editor: the form on the left, a live phone preview on the right.
/// Photos come in by picking several at once or dropping them on the page;
/// the first photo is the cover. Saving, publishing and withdrawing return
/// to the list, where the post shows with its new state.
class AdminArticleEditor extends StatefulWidget {
  const AdminArticleEditor({
    required this.gateway,
    required this.role,
    required this.article,
    required this.onChanged,
    required this.onDeleted,
    required this.onBack,
    this.pickPhotos,
    super.key,
  });

  final AdminEditorialGateway gateway;
  final AdminRole role;
  final AdminEditorialArticle? article;

  /// Reloads the list and re-selects the post; a new post gets its id here.
  final Future<void> Function(String articleId) onChanged;
  final Future<void> Function() onDeleted;
  final VoidCallback onBack;
  final AdminPhotoPicker? pickPhotos;

  /// What a new post's Instagram link starts as: the 술결 account. The
  /// writer swaps in the post's own link when there is one.
  static const defaultInstagramUrl = 'https://www.instagram.com/soolgyul/';

  @override
  State<AdminArticleEditor> createState() => _AdminArticleEditorState();
}

class _AdminArticleEditorState extends State<AdminArticleEditor> {
  final _formKey = GlobalKey<FormState>();
  final _bodyController = TextEditingController();
  final _instagramController = TextEditingController();
  final _picker = ImagePicker();

  late Set<String> _interestKeys;
  bool _busy = false;
  bool _showPreview = false;

  /// `3/5` while photos upload.
  String? _uploadProgress;

  @override
  void initState() {
    super.initState();
    final article = widget.article;
    _interestKeys = Set<String>.from(article?.interestKeys ?? const <String>{});
    _bodyController.text = article?.body ?? '';
    _instagramController.text = article == null
        ? AdminArticleEditor.defaultInstagramUrl
        : article.instagramUrl ?? '';
    _bodyController.addListener(_rebuild);
    _instagramController.addListener(_rebuild);
  }

  @override
  void dispose() {
    _bodyController.dispose();
    _instagramController.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  String? get _instagramUrl {
    final text = _instagramController.text.trim();
    return text.isEmpty ? null : text;
  }

  static final _instagramPostUrl = RegExp(r'^https://(www\.)?instagram\.com/');

  static String? _validateInstagram(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || _instagramPostUrl.hasMatch(text)) return null;
    return 'https://www.instagram.com/ 으로 시작하는 주소를 넣어요.';
  }

  /// Whether the form differs from the saved post.
  bool get _dirty {
    final article = widget.article;
    if (article == null) {
      return _bodyController.text.isNotEmpty ||
          _instagramUrl != AdminArticleEditor.defaultInstagramUrl ||
          _interestKeys.isNotEmpty;
    }
    return _bodyController.text.trim() != article.body ||
        _instagramUrl != article.instagramUrl ||
        !_setEquals(_interestKeys, article.interestKeys);
  }

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  /// Writes the form to the post and returns its id, or `null` when the form
  /// is invalid or the save failed (which is reported). Does not reload the
  /// dashboard, so the editor stays up for whatever follows.
  Future<String?> _persist() async {
    if (!_formKey.currentState!.validate()) return null;
    setState(() => _busy = true);
    try {
      return await widget.gateway.saveArticle(
        AdminArticleDraft(
          id: widget.article?.id,
          body: _bodyController.text.trim(),
          instagramUrl: _instagramUrl,
          status: widget.article?.status ?? AdminArticleStatus.draft,
          interestKeys: _interestKeys,
        ),
      );
    } catch (_) {
      if (mounted) _showMessage('저장하지 못했습니다. 입력값과 권한을 확인해 주세요.');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The save button: store the post and go back to the list.
  Future<void> _save() async {
    final articleId = await _persist();
    if (articleId == null || !mounted) return;
    _showMessage('저장했습니다.');
    _leaveFor(articleId);
  }

  /// Shows the list and reloads it with this post selected.
  void _leaveFor(String articleId) {
    widget.onBack();
    unawaited(widget.onChanged(articleId));
  }

  Future<void> _changeStatus(AdminArticleStatus status) async {
    final publishing = status == AdminArticleStatus.published;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(publishing ? '발행할까요?' : '철회할까요?'),
        content: Text(
          publishing
              ? '저장하지 않은 변경도 함께 저장되고, 앱의 탐색 탭에 바로 보여요.'
              : '앱에서 바로 내려가요. 다시 발행하면 다시 보여요.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey<String>('admin-confirm-status'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(publishing ? '발행' : '철회'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final articleId = widget.article?.id == null || _dirty
        ? await _persist()
        : widget.article!.id;
    if (articleId == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.gateway.changeStatus(articleId, status);
      if (!mounted) return;
      _showMessage(publishing ? '발행했습니다.' : '철회했습니다.');
      _leaveFor(articleId);
    } catch (_) {
      if (mounted) _showMessage('상태를 변경하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDraft() async {
    final article = widget.article;
    if (article == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('초안을 삭제할까요?'),
        content: const Text('한 번도 발행하지 않은 초안만 영구 삭제할 수 있습니다.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.actionDestructive,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.gateway.deleteDraft(article.id);
      if (!mounted) return;
      _showMessage('초안을 삭제했습니다.');
      await widget.onDeleted();
    } catch (_) {
      if (mounted) _showMessage('초안을 삭제하지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (!_dirty) {
      widget.onBack();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('저장하지 않은 변경이 있어요'),
        content: const Text('나가면 바꾼 내용이 사라져요.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 편집'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) widget.onBack();
  }

  // --- Photos ---

  Future<void> _pickPhotos() async {
    final files = await (widget.pickPhotos ?? _pickFromDevice)();
    if (files.isEmpty || !mounted) return;
    await _upload(files);
  }

  Future<List<AdminDroppedFile>> _pickFromDevice() async {
    final files = await _picker.pickMultiImage();
    return <AdminDroppedFile>[
      for (final file in files)
        AdminDroppedFile(name: file.name, bytes: await file.readAsBytes()),
    ];
  }

  /// Dropped files join the gallery in the order they were dropped.
  Future<void> _dropFiles(List<AdminDroppedFile> files) => _upload(files);

  /// Uploads in order, each photo re-encoded as a small JPEG first. A post
  /// that has not been saved yet is saved first, quietly: reloading the
  /// dashboard here would remount this editor and cut the upload short
  /// after the first photo.
  Future<void> _upload(List<AdminDroppedFile> photos) async {
    final accepted = <AdminDroppedFile>[
      for (final photo in photos)
        if (_mediaTypeFor(photo.name) != null) photo,
    ];
    if (accepted.length < photos.length) {
      _showMessage('JPG, PNG, WEBP 이미지만 올릴 수 있어 일부를 건너뛰었어요.');
    }
    if (accepted.isEmpty) return;
    var articleId = widget.article?.id;
    articleId ??= await _persist();
    if (articleId == null || !mounted) return;
    setState(() => _busy = true);
    var uploaded = 0;
    try {
      for (final (index, picked) in accepted.indexed) {
        setState(() => _uploadProgress = '${index + 1}/${accepted.length}');
        final photo = await encodePhotoForUpload(picked);
        await widget.gateway.uploadMedia(
          AdminMediaUpload(
            articleId: articleId,
            fileName: photo.name,
            mediaType: _mediaTypeFor(photo.name)!,
            bytes: photo.bytes,
          ),
        );
        uploaded += 1;
      }
      if (!mounted) return;
      _showMessage('사진 $uploaded장을 올렸어요.');
    } catch (_) {
      if (mounted) {
        _showMessage(
          uploaded == 0
              ? '사진을 올리지 못했어요.'
              : '$uploaded장까지 올리고 멈췄어요. 나머지를 다시 올려 주세요.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploadProgress = null;
        });
        await widget.onChanged(articleId);
      }
    }
  }

  Future<void> _deleteMedia(EditorialMediaAsset media) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사진을 삭제할까요?'),
        content: Text(
          widget.article?.coverMedia?.id == media.id
              ? '첫 사진이라 다음 사진이 표지가 돼요. 저장소에서도 지워져요.'
              : '저장소에서도 지워져요.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.actionDestructive,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _mediaAction(
      () => widget.gateway.deleteMedia(media),
      '사진을 삭제하지 못했어요.',
    );
  }

  /// Moves one photo to another position; whichever ends up first is the
  /// cover.
  Future<void> _reorder(int from, int to) async {
    final article = widget.article;
    if (article == null) return;
    final ids = <String>[for (final value in article.gallery) value.id];
    if (from < 0 || from >= ids.length || to < 0 || to >= ids.length) return;
    final id = ids.removeAt(from);
    ids.insert(to, id);
    await _mediaAction(
      () => widget.gateway.reorderMedia(article.id, ids),
      '사진 순서를 바꾸지 못했어요.',
    );
  }

  Future<void> _mediaAction(
    Future<void> Function() action,
    String failure,
  ) async {
    setState(() => _busy = true);
    try {
      await action();
      final articleId = widget.article?.id;
      if (articleId != null) await widget.onChanged(articleId);
    } catch (_) {
      if (mounted) _showMessage(failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final canDelete =
        widget.role.canDeleteDraft &&
        article?.status == AdminArticleStatus.draft &&
        article?.publishedAt == null;
    final preview = AdminArticlePreview(
      body: _bodyController.text.trim(),
      interestKeys: _interestKeys,
      gallery: article?.gallery ?? const <EditorialMediaAsset>[],
      instagramUrl: _instagramUrl,
    );

    return Form(
      key: _formKey,
      child: Column(
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) => _Header(
              article: article,
              dirty: _dirty,
              busy: _busy,
              compact: constraints.maxWidth < 1100,
              showPreview: _showPreview,
              canPublish: widget.role.canPublish,
              canDelete: canDelete,
              onBack: _leave,
              onTogglePreview: () =>
                  setState(() => _showPreview = !_showPreview),
              onSave: _save,
              onPublish: () => _changeStatus(AdminArticleStatus.published),
              onWithdraw: () => _changeStatus(AdminArticleStatus.withdrawn),
              onDelete: _deleteDraft,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1100;
                final previewPane = ColoredBox(
                  color: AppColors.surfaceSoft,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: preview),
                  ),
                );
                if (wide) {
                  return Row(
                    children: <Widget>[
                      Expanded(child: _buildForm()),
                      const VerticalDivider(width: 1),
                      SizedBox(width: 420, child: previewPane),
                    ],
                  );
                }
                return _showPreview ? previewPane : _buildForm();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final article = widget.article;
    return AdminFileDrop(
      enabled: !_busy,
      onFiles: _dropFiles,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        children: <Widget>[
          AdminSection(
            title: '사진',
            description: '첫 사진이 탐색 탭의 표지가 되고, 독자는 이 순서대로 넘겨 봐요.',
            trailing: FilledButton.tonalIcon(
              key: const ValueKey<String>('admin-upload-content'),
              onPressed: _busy ? null : _pickPhotos,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('사진 추가'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_uploadProgress case final progress?) ...<Widget>[
                  Row(
                    children: <Widget>[
                      const Expanded(child: LinearProgressIndicator()),
                      const SizedBox(width: AppSpacing.md),
                      Text('올리는 중 $progress', style: AppTextStyles.caption),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                _DropZone(enabled: !_busy, onTap: _pickPhotos),
                const SizedBox(height: AppSpacing.lg),
                _GalleryStrip(
                  media: article?.gallery ?? const <EditorialMediaAsset>[],
                  enabled: !_busy,
                  onDelete: _deleteMedia,
                  onReorder: _reorder,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AdminSection(
            title: '글',
            description: '사진만으로 충분한 카드뉴스는 비워 둬도 돼요. 첫 줄이 관리자 목록의 이름이 돼요.',
            child: TextFormField(
              key: const ValueKey<String>('admin-body'),
              controller: _bodyController,
              minLines: 10,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textPrimary,
                height: 1.7,
              ),
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                hintText: '줄바꿈이 있는 보통 글로 적어요.',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AdminSection(
            title: '노출',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextFormField(
                  key: const ValueKey<String>('admin-instagram-url'),
                  controller: _instagramController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '인스타그램 게시글 링크',
                    hintText: 'https://www.instagram.com/p/…',
                    helperText:
                        '글 머리글의 인스타그램 버튼이 여는 주소예요. 새 글은 술결 계정으로 시작하고, 게시글 링크로 바꿔도 돼요. 비우면 버튼이 없어요.',
                  ),
                  validator: _validateInstagram,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('관심 주종', style: AppTextStyles.sectionTitleSm),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '고른 주종의 해시태그로 걸러져요. 아무것도 고르지 않으면 모든 독자에게 보여요.',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final interest in DrinkInterest.values)
                      FilterChip(
                        label: Text(interest.label),
                        selected: _interestKeys.contains(interest.wireKey),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _interestKeys.add(interest.wireKey);
                          } else {
                            _interestKeys.remove(interest.wireKey);
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.massive),
        ],
      ),
    );
  }

  static String? _mediaTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return null;
  }
}

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
                  color: index == 0
                      ? AppColors.actionPrimary
                      : AppColors.scrimStrong,
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
