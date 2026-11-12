import '../features/editorial/data/editorial_article.dart';

enum AdminRole {
  editor,
  admin;

  bool get canPublish => this == admin;
  bool get canDeleteDraft => this == admin;

  static AdminRole? fromWire(String? value) => switch (value) {
    'editor' => AdminRole.editor,
    'admin' => AdminRole.admin,
    _ => null,
  };
}

enum AdminArticleStatus {
  draft,
  published,
  withdrawn;

  String get wireValue => name;

  String get label => switch (this) {
    AdminArticleStatus.draft => '초안',
    AdminArticleStatus.published => '발행',
    AdminArticleStatus.withdrawn => '철회',
  };

  static AdminArticleStatus fromWire(String value) => switch (value) {
    'published' => AdminArticleStatus.published,
    'withdrawn' => AdminArticleStatus.withdrawn,
    _ => AdminArticleStatus.draft,
  };
}

class AdminAuthSession {
  const AdminAuthSession({required this.userId, this.email});

  final String userId;
  final String? email;
}

class AdminEditorialArticle {
  const AdminEditorialArticle({
    required this.id,
    required this.body,
    required this.status,
    required this.mediaAssets,
    required this.interestKeys,
    required this.updatedAt,
    this.publishedAt,
    this.instagramUrl,
  });

  final String id;
  final String body;

  /// The same post on Instagram, if the editor linked it.
  final String? instagramUrl;
  final AdminArticleStatus status;
  final DateTime? publishedAt;
  final DateTime updatedAt;

  /// Photos in gallery order; the first one is the cover.
  final List<EditorialMediaAsset> mediaAssets;
  final Set<String> interestKeys;

  EditorialMediaAsset? get coverMedia =>
      mediaAssets.isEmpty ? null : mediaAssets.first;

  List<EditorialMediaAsset> get gallery => mediaAssets;

  /// What the console calls the post: the first line of its text.
  String get label => adminArticleLabel(body);
}

/// The first line of a post's text, or a stand-in for a post of photos only.
String adminArticleLabel(String body) {
  final line = body.trim().split('\n').first.trim();
  return line.isEmpty ? '(사진만 있는 글)' : line;
}

class AdminArticleDraft {
  const AdminArticleDraft({
    required this.body,
    required this.status,
    required this.interestKeys,
    this.id,
    this.instagramUrl,
  });

  final String? id;
  final String body;
  final AdminArticleStatus status;
  final Set<String> interestKeys;
  final String? instagramUrl;
}

class AdminEditorialBootstrap {
  const AdminEditorialBootstrap({required this.role, required this.articles});

  final AdminRole role;
  final List<AdminEditorialArticle> articles;
}

class AdminMediaUpload {
  const AdminMediaUpload({
    required this.articleId,
    required this.fileName,
    required this.mediaType,
    required this.bytes,
  });

  final String articleId;
  final String fileName;

  /// The file's type, which Storage serves the photo with.
  final String mediaType;
  final List<int> bytes;
}

/// What a site post is on soolgyul.com: a notice, or one FAQ answer.
enum AdminSitePostKind {
  notice,
  faq;

  String get wireValue => name;

  String get label => switch (this) {
    AdminSitePostKind.notice => '공지사항',
    AdminSitePostKind.faq => 'FAQ',
  };

  static AdminSitePostKind fromWire(String value) =>
      value == 'faq' ? AdminSitePostKind.faq : AdminSitePostKind.notice;
}

/// A notice or an FAQ answer: the title (an FAQ's question), the plain text
/// under it, and for FAQ answers their place in the list.
class AdminSitePost {
  const AdminSitePost({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.sortOrder,
    required this.status,
    required this.updatedAt,
    this.publishedAt,
  });

  final String id;
  final AdminSitePostKind kind;
  final String title;
  final String body;
  final int sortOrder;
  final AdminArticleStatus status;
  final DateTime? publishedAt;
  final DateTime updatedAt;
}

class AdminSitePostDraft {
  const AdminSitePostDraft({
    required this.kind,
    required this.title,
    required this.body,
    required this.sortOrder,
    required this.status,
    this.id,
  });

  final String? id;
  final AdminSitePostKind kind;
  final String title;
  final String body;
  final int sortOrder;
  final AdminArticleStatus status;
}

/// A member's question from the app's support form, as the inbox shows it.
class AdminSupportInquiry {
  const AdminSupportInquiry({
    required this.id,
    required this.type,
    required this.replyEmail,
    required this.content,
    required this.attachmentPaths,
    required this.createdAt,
    this.answeredAt,
  });

  final String id;
  final AdminSupportInquiryType type;
  final String replyEmail;
  final String content;
  final List<String> attachmentPaths;
  final DateTime createdAt;
  final DateTime? answeredAt;
}

enum AdminSupportInquiryType {
  bug('오류 신고'),
  usage('이용 문의'),
  suggestion('기능 제안'),
  other('기타');

  const AdminSupportInquiryType(this.label);

  final String label;

  static AdminSupportInquiryType fromWire(String value) =>
      values.firstWhere((type) => type.name == value, orElse: () => other);
}

/// How many members and phones a marketing notification reaches now, and
/// the sends so far, newest first.
class AdminMarketingPushOverview {
  const AdminMarketingPushOverview({
    required this.memberCount,
    required this.deviceCount,
    required this.pushes,
  });

  final int memberCount;
  final int deviceCount;
  final List<AdminMarketingPush> pushes;
}

/// One marketing notification an admin sent, with the words as typed.
class AdminMarketingPush {
  const AdminMarketingPush({
    required this.id,
    required this.title,
    required this.body,
    required this.startedAt,
    this.finishedAt,
    this.deviceCount,
    this.sentCount,
  });

  final String id;
  final String title;
  final String body;
  final DateTime startedAt;

  /// Null when the send was cut short; the counts are then unknown.
  final DateTime? finishedAt;
  final int? deviceCount;
  final int? sentCount;
}

/// How a send ended: the phones it went to and how many the notification
/// service took.
class AdminMarketingPushResult {
  const AdminMarketingPushResult({
    required this.deviceCount,
    required this.sentCount,
  });

  final int deviceCount;
  final int sentCount;
}
