import '../../features/editorial/data/editorial_article.dart';
import '../admin_editorial_models.dart';

abstract interface class AdminEditorialGateway {
  AdminAuthSession? get currentSession;

  Stream<AdminAuthSession?> get sessionChanges;

  /// Signs in with the login id and password of an account the Supabase
  /// dashboard created. Throws with `invalidCredentials` when they do not
  /// match.
  Future<void> signIn({required String loginId, required String password});

  Future<void> signOut();

  Future<AdminEditorialBootstrap?> loadBootstrap();

  Future<List<AdminEditorialArticle>> fetchArticles();

  Future<String> saveArticle(AdminArticleDraft draft);

  Future<void> changeStatus(String articleId, AdminArticleStatus status);

  Future<void> deleteDraft(String articleId);

  Future<EditorialMediaAsset> uploadMedia(AdminMediaUpload upload);

  Future<void> deleteMedia(EditorialMediaAsset media);

  /// Stores the gallery order of an article's photos: the first id gets
  /// sort order 0 and is the cover, the next 1, and so on.
  Future<void> reorderMedia(String articleId, List<String> mediaIds);

  /// Every notice and FAQ answer, whatever its status.
  Future<List<AdminSitePost>> fetchSitePosts();

  /// Inserts a draft without an id, else updates it; returns the id.
  Future<String> saveSitePost(AdminSitePostDraft draft);

  Future<void> deleteSitePost(String id);

  /// The newest support inquiries, open ones first. Admins only; the
  /// database logs every read.
  Future<List<AdminSupportInquiry>> fetchSupportInquiries();

  /// Marks an inquiry answered, or open again.
  Future<void> setSupportInquiryAnswered(String id, {required bool answered});

  /// Short-lived links to an inquiry's photos, in the given order.
  Future<List<String>> inquiryPhotoUrls(List<String> paths);

  /// Whom a marketing notification reaches now, and the sends so far.
  /// Admins only.
  Future<AdminMarketingPushOverview> loadMarketingPushOverview();

  /// Sends a marketing notification to the members who agreed to marketing
  /// and have notifications on. [id] names the send: asked again with the
  /// same id, it is not sent a second time. Throws
  /// [AdminMarketingPushException] when nothing was confirmed sent.
  Future<AdminMarketingPushResult> sendMarketingPush({
    required String id,
    required String title,
    required String body,
  });
}

enum AdminEditorialOperation {
  signIn,
  signOut,
  load,
  save,
  publish,
  withdraw,
  delete,
  upload,
  deleteMedia,
  reorderMedia,
}

class AdminEditorialException implements Exception {
  const AdminEditorialException(this.operation, [this.message]);

  static const invalidCredentials = 'invalid_credentials';

  final AdminEditorialOperation operation;
  final String? message;
}

/// Why the server refused a marketing notification.
enum AdminMarketingPushRefusal {
  /// Marketing notifications are not sent from 9 at night to 8 in the morning.
  nightHours,

  /// A send with this id was already started.
  alreadySent,
}

class AdminMarketingPushException implements Exception {
  const AdminMarketingPushException([this.refusal]);

  /// Null when the send failed for a reason the admin cannot act on.
  final AdminMarketingPushRefusal? refusal;
}
