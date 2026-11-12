import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/error_report.dart';
import '../../features/editorial/data/editorial_article.dart';
import '../admin_editorial_models.dart';
import 'admin_editorial_gateway.dart';

class SupabaseAdminEditorialGateway implements AdminEditorialGateway {
  SupabaseAdminEditorialGateway(this._client);

  static const editorialBucket = 'soolgyul-editorial';
  static const privateBucket = 'soolgyul-private';

  /// Administrator accounts are Supabase email accounts the dashboard
  /// creates as `<login id>@admin.soolgyul.com`; the screen asks for the id.
  static const loginDomain = 'admin.soolgyul.com';

  static String loginEmail(String loginId) =>
      '${loginId.trim().toLowerCase()}@$loginDomain';

  final SupabaseClient _client;

  static const _articleSelect = '''
    id,
    body,
    instagram_url,
    status,
    published_at,
    updated_at,
    media:editorial_article_media_assets(
      id,
      storage_bucket,
      storage_object_path,
      sort_order
    ),
    interest_links:editorial_article_interests(
      interest_key
    )
  ''';

  @override
  AdminAuthSession? get currentSession =>
      _sessionFromUser(_client.auth.currentSession?.user);

  @override
  Stream<AdminAuthSession?> get sessionChanges => _client.auth.onAuthStateChange
      .map((state) => _sessionFromUser(state.session?.user))
      .distinct((left, right) => left?.userId == right?.userId);

  @override
  Future<void> signIn({
    required String loginId,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(
        email: loginEmail(loginId),
        password: password,
      );
    } on AuthException catch (error, stack) {
      // A wrong id or password is an answer, not a fault. Other 400s (a
      // locked or unconfirmed account) fall through to a plain failure.
      if (error.code == AdminEditorialException.invalidCredentials) {
        throw const AdminEditorialException(
          AdminEditorialOperation.signIn,
          AdminEditorialException.invalidCredentials,
        );
      }
      _fail(AdminEditorialOperation.signIn, error, stack);
    } catch (error, stack) {
      _fail(AdminEditorialOperation.signIn, error, stack);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (error, stack) {
      _fail(AdminEditorialOperation.signOut, error, stack);
    }
  }

  @override
  Future<AdminEditorialBootstrap?> loadBootstrap() async {
    try {
      final session = currentSession;
      if (session == null) return null;
      final roleRows = await _client
          .from('admin_user_roles')
          .select('role')
          .eq('user_id', session.userId)
          .limit(1);
      if (roleRows.isEmpty) return null;
      final role = AdminRole.fromWire(roleRows.first['role'] as String?);
      if (role == null) return null;

      return AdminEditorialBootstrap(
        role: role,
        articles: await fetchArticles(),
      );
    } on AdminEditorialException {
      rethrow;
    } catch (error, stack) {
      _fail(AdminEditorialOperation.load, error, stack);
    }
  }

  @override
  Future<List<AdminEditorialArticle>> fetchArticles() async {
    try {
      final response = await _client
          .from('editorial_articles')
          .select(_articleSelect)
          .order('updated_at', ascending: false);
      return List<AdminEditorialArticle>.unmodifiable(<AdminEditorialArticle>[
        for (final value in response)
          _articleFromMap(Map<String, dynamic>.from(value)),
      ]);
    } catch (error, stack) {
      _fail(AdminEditorialOperation.load, error, stack);
    }
  }

  @override
  Future<String> saveArticle(AdminArticleDraft draft) async {
    try {
      final response = await _client.rpc<dynamic>(
        'soolgyul_admin_save_editorial_article',
        params: <String, dynamic>{
          'article_id': draft.id,
          'article_body': draft.body,
          'article_status': draft.status.wireValue,
          'interest_keys': draft.interestKeys.toList(),
          'instagram_link': draft.instagramUrl,
        },
      );
      return response as String;
    } catch (error, stack) {
      _fail(AdminEditorialOperation.save, error, stack);
    }
  }

  @override
  Future<void> changeStatus(String articleId, AdminArticleStatus status) async {
    try {
      await _client.rpc<void>(
        'soolgyul_admin_change_editorial_status',
        params: <String, dynamic>{
          'article_id': articleId,
          'next_status': status.wireValue,
        },
      );
    } catch (error, stack) {
      _fail(
        status == AdminArticleStatus.published
            ? AdminEditorialOperation.publish
            : AdminEditorialOperation.withdraw,
        error,
        stack,
      );
    }
  }

  @override
  Future<void> deleteDraft(String articleId) async {
    try {
      await _client.rpc<void>(
        'soolgyul_admin_delete_editorial_draft',
        params: <String, dynamic>{'article_id': articleId},
      );
    } catch (error, stack) {
      _fail(AdminEditorialOperation.delete, error, stack);
    }
  }

  @override
  Future<EditorialMediaAsset> uploadMedia(AdminMediaUpload upload) async {
    final safeName = _safeFileName(upload.fileName);
    final path =
        '${upload.articleId}/${DateTime.now().microsecondsSinceEpoch}_$safeName';
    try {
      await _client.storage
          .from(editorialBucket)
          .uploadBinary(
            path,
            Uint8List.fromList(upload.bytes),
            fileOptions: FileOptions(
              contentType: upload.mediaType,
              upsert: false,
            ),
          );
    } catch (error, stack) {
      _fail(AdminEditorialOperation.upload, error, stack);
    }
    try {
      final existing = await _client
          .from('editorial_article_media_assets')
          .select('sort_order')
          .eq('article_id', upload.articleId);
      final nextOrder = existing.isEmpty
          ? 0
          : 1 +
                existing
                    .map((row) => row['sort_order'] as int)
                    .reduce((a, b) => a > b ? a : b);
      final inserted = await _client
          .from('editorial_article_media_assets')
          .insert(<String, dynamic>{
            'article_id': upload.articleId,
            'storage_bucket': editorialBucket,
            'storage_object_path': path,
            'sort_order': nextOrder,
          })
          .select('id, storage_bucket, storage_object_path, sort_order')
          .single();
      return _mediaFromMap(Map<String, dynamic>.from(inserted));
    } catch (error, stack) {
      // Without its row nothing points at the file; take it back out.
      await _removeStoredFile(editorialBucket, path);
      _fail(AdminEditorialOperation.upload, error, stack);
    }
  }

  /// Deletes the row first, so a refused delete leaves the photo whole;
  /// the file goes after, and a file left behind only takes space.
  @override
  Future<void> deleteMedia(EditorialMediaAsset media) async {
    final List<Map<String, dynamic>> deleted;
    try {
      deleted = await _client
          .from('editorial_article_media_assets')
          .delete()
          .eq('id', media.id)
          .select('id');
    } catch (error, stack) {
      _fail(AdminEditorialOperation.deleteMedia, error, stack);
    }
    // A row the account may not delete is hidden from it, so nothing
    // deleted is a refusal, not a success.
    if (deleted.isEmpty) {
      throw const AdminEditorialException(AdminEditorialOperation.deleteMedia);
    }
    if (media.storageBucket != 'flutter-assets') {
      await _removeStoredFile(media.storageBucket, media.storageObjectPath);
    }
  }

  @override
  Future<void> reorderMedia(String articleId, List<String> mediaIds) async {
    try {
      for (var index = 0; index < mediaIds.length; index++) {
        await _client
            .from('editorial_article_media_assets')
            .update(<String, dynamic>{'sort_order': index})
            .eq('id', mediaIds[index])
            .eq('article_id', articleId);
      }
    } catch (error, stack) {
      _fail(AdminEditorialOperation.reorderMedia, error, stack);
    }
  }

  @override
  Future<List<AdminSitePost>> fetchSitePosts() async {
    try {
      final response = await _client
          .from('site_posts')
          .select(
            'id, kind, title, body, sort_order, status, published_at, updated_at',
          )
          .order('sort_order')
          .order('updated_at', ascending: false);
      return List<AdminSitePost>.unmodifiable(<AdminSitePost>[
        for (final value in response)
          AdminSitePost(
            id: value['id'] as String,
            kind: AdminSitePostKind.fromWire(value['kind'] as String),
            title: value['title'] as String,
            body: value['body'] as String,
            sortOrder: value['sort_order'] as int,
            status: AdminArticleStatus.fromWire(value['status'] as String),
            publishedAt: _parseDate(value['published_at']),
            updatedAt: DateTime.parse(value['updated_at'] as String),
          ),
      ]);
    } catch (error, stack) {
      _fail(AdminEditorialOperation.load, error, stack);
    }
  }

  @override
  Future<List<AdminSupportInquiry>> fetchSupportInquiries() async {
    try {
      final response = await _client.rpc<List<dynamic>>(
        'soolgyul_admin_list_support_inquiries',
      );
      return List<AdminSupportInquiry>.unmodifiable(<AdminSupportInquiry>[
        for (final value in response.cast<Map<String, dynamic>>())
          AdminSupportInquiry(
            id: value['id'] as String,
            type: AdminSupportInquiryType.fromWire(
              value['inquiry_type'] as String,
            ),
            replyEmail: value['reply_email'] as String,
            content: value['content'] as String,
            attachmentPaths: List<String>.unmodifiable(
              (value['attachment_paths'] as List<dynamic>).cast<String>(),
            ),
            createdAt: DateTime.parse(value['created_at'] as String),
            answeredAt: _parseDate(value['answered_at']),
          ),
      ]);
    } catch (error, stack) {
      _fail(AdminEditorialOperation.load, error, stack);
    }
  }

  @override
  Future<void> setSupportInquiryAnswered(
    String id, {
    required bool answered,
  }) async {
    try {
      await _client.rpc<void>(
        'soolgyul_admin_set_support_inquiry_answered',
        params: <String, dynamic>{'inquiry_id': id, 'answered': answered},
      );
    } catch (error, stack) {
      _fail(AdminEditorialOperation.save, error, stack);
    }
  }

  @override
  Future<List<String>> inquiryPhotoUrls(List<String> paths) async {
    if (paths.isEmpty) return const <String>[];
    try {
      final signed = await _client.storage
          .from(privateBucket)
          .createSignedUrlsResult(paths, 600);
      // A photo gone from storage is left out.
      return <String>[
        for (final result in signed)
          if (result case SignedUrlSuccess(:final signedUrl)) signedUrl,
      ];
    } catch (error, stack) {
      _fail(AdminEditorialOperation.load, error, stack);
    }
  }

  @override
  Future<String> saveSitePost(AdminSitePostDraft draft) async {
    final values = <String, dynamic>{
      'kind': draft.kind.wireValue,
      'title': draft.title,
      'body': draft.body,
      'sort_order': draft.sortOrder,
      'status': draft.status.wireValue,
    };
    try {
      final id = draft.id;
      final saved = id == null
          ? await _client
                .from('site_posts')
                .insert(values)
                .select('id')
                .single()
          : await _client
                .from('site_posts')
                .update(values)
                .eq('id', id)
                .select('id')
                .single();
      return saved['id'] as String;
    } catch (error, stack) {
      _fail(AdminEditorialOperation.save, error, stack);
    }
  }

  @override
  Future<void> deleteSitePost(String id) async {
    try {
      await _client.from('site_posts').delete().eq('id', id);
    } catch (error, stack) {
      _fail(AdminEditorialOperation.delete, error, stack);
    }
  }

  /// Best effort: a file that will not go is reported and left.
  Future<void> _removeStoredFile(String bucket, String path) async {
    try {
      await _client.storage.from(bucket).remove(<String>[path]);
    } catch (error, stack) {
      reportError(error, stack, where: 'admin:removeFile');
    }
  }

  /// Hands the cause to the error report and throws the console's own
  /// failure in its place, with the cause's stack.
  static Never _fail(
    AdminEditorialOperation operation,
    Object error,
    StackTrace stack,
  ) {
    reportError(error, stack, where: 'admin:${operation.name}');
    Error.throwWithStackTrace(AdminEditorialException(operation), stack);
  }

  AdminEditorialArticle _articleFromMap(Map<String, dynamic> value) {
    final mediaValues = value['media'] as List? ?? const <dynamic>[];
    final media = <EditorialMediaAsset>[
      for (final raw in mediaValues)
        _mediaFromMap(Map<String, dynamic>.from(raw as Map)),
    ]..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    final links = value['interest_links'] as List? ?? const <dynamic>[];
    return AdminEditorialArticle(
      id: value['id'] as String,
      body: value['body'] as String,
      instagramUrl: value['instagram_url'] as String?,
      status: AdminArticleStatus.fromWire(value['status'] as String),
      publishedAt: _parseDate(value['published_at']),
      updatedAt: DateTime.parse(value['updated_at'] as String),
      mediaAssets: List<EditorialMediaAsset>.unmodifiable(media),
      interestKeys: Set<String>.unmodifiable(<String>{
        for (final raw in links) (raw as Map)['interest_key'] as String,
      }),
    );
  }

  EditorialMediaAsset _mediaFromMap(Map<String, dynamic> value) {
    final bucket = value['storage_bucket'] as String;
    final path = value['storage_object_path'] as String;
    return EditorialMediaAsset(
      id: value['id'] as String,
      storageBucket: bucket,
      storageObjectPath: path,
      sortOrder: value['sort_order'] as int,
      publicUrl: bucket == 'flutter-assets'
          ? null
          : _client.storage.from(bucket).getPublicUrl(path),
    );
  }

  AdminAuthSession? _sessionFromUser(User? user) {
    if (user == null) return null;
    return AdminAuthSession(userId: user.id, email: user.email);
  }

  static DateTime? _parseDate(dynamic value) {
    return value is String ? DateTime.parse(value) : null;
  }

  static String _safeFileName(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp('[^a-z0-9._-]+'),
      '-',
    );
    return normalized.isEmpty ? 'image' : normalized;
  }
}
